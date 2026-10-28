defmodule TigooServerWeb.Plugs.FeRequestCapture do
  @moduledoc "Opt-in, private capture of FE communication requests for offline inspection."
  import Plug.Conn
  require Logger

  @limit 8_000_000
  @services ~w(autenticacion recepcion aprobacioncomercial)

  def init(opts), do: opts

  def call(conn, _opts) do
    config = Application.get_env(:tigoo_server, :fe_authentication, [])
    root = Keyword.get(config, :capture_directory)

    if is_binary(root) and root != "" and fe_request?(conn) do
      directory = Path.join([Path.expand(root), "requests", Ecto.UUID.generate()])
      File.mkdir_p!(directory)
      File.chmod!(Path.expand(root), 0o700)
      File.chmod!(Path.dirname(directory), 0o700)
      File.chmod!(directory, 0o700)
      write_json(directory, "request.json", %{
        captured_at: DateTime.to_iso8601(DateTime.utc_now()),
        request_id: Logger.metadata()[:request_id], method: conn.method,
        host: conn.host, path: conn.request_path,
        headers: redact_headers(conn.req_headers),
        authorization_sha256: header_hash(conn, "authorization")
      })
      capture_resources(directory, config)
      Logger.info("FE capture stage=request directory=#{inspect(directory)}")

      conn
      |> put_private(:fe_capture, %{directory: directory, body_bytes: 0})
      |> register_before_send(&capture_response/1)
    else
      conn
    end
  rescue
    exception ->
      log_failure(:request, exception)
      conn
  end

  # Plug's body_reader handles JSON/form requests, but not multipart requests.
  # Use the multipart callback below to preserve all uploaded parts unchanged.
  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {status, body, conn} when status in [:ok, :more] ->
        {status, body, capture_body(conn, body)}
      other -> other
    end
  end

  def multipart_to_params(parts, conn) do
    capture_multipart(conn, parts)
    Plug.Parsers.MULTIPART.multipart_to_params(parts, conn, [])
  end

  defp fe_request?(conn) do
    case Enum.map(conn.path_info, &(URI.decode(&1) |> String.normalize(:nfc) |> String.downcase())) do
      ["fe", service, "api" | _] -> service in @services or service == "recepción"
      _ -> false
    end
  end

  defp capture_resources(directory, config) do
    resources = for {key, label} <- [trusted_certificates: "root", intermediate_certificates: "intermediate", crls: "crl"],
                    {path, index} <- Enum.with_index(Keyword.get(config, key, []), 1) do
      filename = "#{label}-#{index}." <> if(key == :crls, do: "crl", else: "crt")
      case File.read(path) do
        {:ok, bytes} when byte_size(bytes) <= @limit ->
          write(directory, filename, bytes)
          %{file: filename, source: path, sha256: sha256(bytes)}
        _ -> %{file: filename, source: path, unavailable: true}
      end
    end
    write_json(directory, "verifier-resources.json", %{
      xmlsec_path: Keyword.get(config, :xmlsec_path, "xmlsec1"),
      openssl_path: Keyword.get(config, :openssl_path, "openssl"), files: resources
    })
  end

  defp capture_body(%{private: %{fe_capture: capture}} = conn, body) do
    size = capture.body_bytes + byte_size(body)
    if size <= @limit do
      path = Path.join(capture.directory, "request-body.bin")
      File.write!(path, body, [:binary, :append])
      File.chmod!(path, 0o600)
    end
    put_private(conn, :fe_capture, %{capture | body_bytes: size})
  rescue
    exception ->
      log_failure(:body, exception)
      conn
  end
  defp capture_body(conn, _), do: conn

  defp capture_multipart(%{private: %{fe_capture: capture}}, parts) do
    files = for {{name, headers, part}, index} <- Enum.with_index(Enum.reverse(parts), 1) do
      {bytes, original} = case part do
        %Plug.Upload{path: path, filename: filename} -> {File.read!(path), filename}
        bytes when is_binary(bytes) -> {bytes, nil}
      end
      extension = if String.valid?(bytes) and String.starts_with?(String.trim_leading(bytes), "<"), do: "xml", else: "bin"
      filename = "part-#{index}.#{extension}"
      sensitive = is_binary(name) and String.downcase(name) in ~w(token password authorization)
      saved = byte_size(bytes) <= @limit and not sensitive
      if saved do
        write(capture.directory, filename, bytes)
        capture_certificates(capture.directory, filename, bytes)
      end
      %{field: name, original_filename: original, file: if(saved, do: filename),
        bytes: byte_size(bytes), sha256: sha256(bytes), headers: redact_headers(headers),
        omitted: if(saved, do: nil, else: "sensitive field or capture size limit")}
    end
    write_json(capture.directory, "multipart.json", %{parts: files})
  rescue
    exception -> log_failure(:multipart, exception)
  end
  defp capture_multipart(_, _), do: :ok

  defp capture_certificates(directory, filename, bytes) do
    if String.valid?(bytes) and not String.contains?(bytes, ["<!DOCTYPE", "<!ENTITY", "\0"]) do
      case Saxy.SimpleForm.parse_string(bytes, expand_entity: {TigooServer.Sign, :reject_entity, []}) do
        {:ok, root} ->
          for {encoded, index} <- Enum.with_index(Enum.take(certificates(root), 20), 1),
              {:ok, der} <- [Base.decode64(String.replace(encoded, ~r/\s+/, ""))] do
            :public_key.pkix_decode_cert(der, :otp)
            pem = :public_key.pem_encode([{:Certificate, der, :not_encrypted}])
            write(directory, "#{filename}-certificate-#{index}.pem", pem)
          end
        _ -> :ok
      end
    end
  rescue
    exception -> log_failure(:certificate_extraction, exception)
  end

  defp certificates({name, _, children}) do
    if List.last(String.split(name, ":")) == "X509Certificate" do
      [Enum.filter(children, &is_binary/1) |> Enum.join()]
    else
      children |> Enum.filter(&is_tuple/1) |> Enum.flat_map(&certificates/1)
    end
  end

  defp capture_response(%{private: %{fe_capture: capture}} = conn) do
    body = IO.iodata_to_binary(conn.resp_body || "")
    token_response = conn.status == 200 and String.ends_with?(String.downcase(conn.request_path), "/validacioncertificado")
    body = if token_response, do: redact_token(body), else: body
    if byte_size(body) <= @limit, do: write(capture.directory, "response-body.bin", body)
    write_json(capture.directory, "response.json", %{
      status: conn.status, headers: redact_headers(conn.resp_headers),
      body_bytes: byte_size(body), body_sha256: sha256(body), token_redacted: token_response,
      request_body_truncated: capture.body_bytes > @limit
    })
    conn
  rescue
    exception ->
      log_failure(:response, exception)
      conn
  end

  defp redact_token(body) do
    case Jason.decode(body) do
      {:ok, %{} = data} -> Jason.encode!(Map.put(data, "token", "[REDACTED]"))
      _ -> Regex.replace(~r/(<token>)[^<]*(<\/token>)/, body, "\\1[REDACTED]\\2")
    end
  end

  defp redact_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      %{name: name, value: if(String.downcase(name) in ~w(authorization cookie set-cookie proxy-authorization), do: "[REDACTED]", else: value)}
    end)
  end

  defp header_hash(conn, name) do
    case get_req_header(conn, name) do
      [value] -> sha256(value)
      _ -> nil
    end
  end

  defp write(directory, filename, bytes) do
    path = Path.join(directory, filename)
    File.write!(path, bytes, [:binary, :exclusive])
    File.chmod!(path, 0o600)
  end
  defp write_json(directory, filename, data), do: write(directory, filename, Jason.encode!(data, pretty: true))
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp log_failure(stage, exception), do: Logger.warning("FE capture stage=#{stage} result=unavailable exception=#{inspect(exception.__struct__)}")
end
