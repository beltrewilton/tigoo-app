defmodule TigooServer.Fe.Client do
  @moduledoc """
  DGII REST client: seed/sign/token, ECF reception, RFCE reception and track queries.

  `new/1` builds a client without HTTP calls. `authenticate/1` returns
  `{:ok, client}`. Document and result calls return `{:ok, body, updated_client}`
  or `{:error, %Error{}}`; keep the returned client to reuse refreshed tokens.
  An HTTP-successful fiscal rejection is still an `:ok` response: inspect
  `status/2`. Requests never retry or follow redirects automatically.
  """
  alias TigooServer.Fe.Credentials
  alias TigooServer.Sign
  alias TigooServer.Fe.Client.Error
  alias TigooServer.Fe.Generation.{Rules, Xml}
  @derive {Inspect, except: [:password, :token]}
  defstruct [:issuer_rnc, :p12_path, :password, :token, :expires_at, :issued_at,
    :certificate_sha256, environment: "certecf", receive_timeout: 60_000, sign_options: []]
  @type t :: %__MODULE__{}
  @environments ~w(certecf testecf ecf)

  @spec new(keyword()) :: t()
  def new(opts) do
    environment = Keyword.get(opts, :environment, "certecf")
    issuer = Keyword.get(opts, :issuer_rnc) || raise(ArgumentError, "Missing issuer_rnc")
    identity = (Keyword.get(opts, :p12_path) || raise(ArgumentError, "Missing p12_path")) |> Path.expand()
    timeout = Keyword.get(opts, :receive_timeout, 60_000)
    unless environment in @environments, do: raise(ArgumentError, "Environment must be certecf, testecf or ecf")
    unless is_binary(issuer) and Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, issuer), do: raise(ArgumentError, "Invalid issuer RNC")
    unless File.regular?(identity), do: raise(ArgumentError, "Signing identity is unavailable")
    unless is_integer(timeout) and timeout > 0, do: raise(ArgumentError, "receive_timeout must be positive")
    password = Credentials.password!(opts)
    Enum.each([:req, :public_key], fn app ->
      case Application.ensure_all_started(app) do
        {:ok, _} -> :ok
        {:error, _} -> raise ArgumentError, "Cannot start #{app} for the DGII client"
      end
    end)
    %__MODULE__{environment: environment, issuer_rnc: issuer, p12_path: identity,
      password: password, receive_timeout: timeout,
      sign_options: Keyword.take(opts, [:xmlsec_path, :openssl_path])}
  end

  @doc "Gets DGII's seed, signs it with the existing signer, and exchanges it for a token."
  @spec authenticate(t()) :: {:ok, t()} | {:error, Error.t()}
  def authenticate(%__MODULE__{} = client) do
    with {:ok, seed} <- request(client, :seed, :get, endpoint(client, :auth) <> "/api/Autenticacion/Semilla", [headers: [{"accept", "application/xml"}]]),
         :ok <- seed_document(seed),
         {:ok, signed} <- sign_seed(client, seed),
         {:ok, response} <- upload(client, :authenticate, endpoint(client, :auth) <> "/api/Autenticacion/ValidarSemilla", signed, "semilla.xml", false),
         {:ok, authenticated} <- session(client, response, signed) do
      {:ok, authenticated}
    end
  rescue
    error in UndefinedFunctionError ->
      failure(:authenticate, "DGII authentication function unavailable: #{inspect(error.module)}.#{error.function}/#{error.arity}")
    error in TigooServer.Fe.Generation.Error ->
      failure(:authenticate, "DGII authentication XML error: #{Exception.message(error)}")
    error ->
      failure(:authenticate, "DGII authentication failed unexpectedly (#{inspect(error.__struct__)})")
  end

  @doc "Posts unchanged signed ECF bytes. Type 32 below DOP 250000 is refused here."
  @spec send_ecf(t(), Path.t(), keyword()) :: {:ok, map(), t()} | {:error, Error.t()}
  def send_ecf(client, path, opts \\ []), do: send_document(client, :ecf, path, opts)

  @doc "Posts a signed RFCE to the separate fc.dgii.gov.do service."
  @spec send_rfce(t(), Path.t(), keyword()) :: {:ok, map(), t()} | {:error, Error.t()}
  def send_rfce(client, path, opts \\ []), do: send_document(client, :rfce, path, opts)

  @doc "Queries a previously received ECF track ID; does not repost the document."
  @spec result(t(), String.t()) :: {:ok, map(), t()} | {:error, Error.t()}
  def result(client, track_id) when is_binary(track_id) and byte_size(track_id) > 0 do
    with {:ok, client} <- ensure_token(client),
         {:ok, body} <- request(client, :result, :get, endpoint(client, :result) <> "/api/Consultas/Estado",
           [headers: headers(client), params: [{"TrackId", track_id}]]) do
      {:ok, body, client}
    end
  end

  defp send_document(client, kind, path, opts) do
    with {:ok, xml, filename, signature} <- document(client, kind, path, opts),
         {:ok, client} <- ensure_token(client),
         :ok <- same_signer(client, signature),
         {:ok, body} <- upload(client, kind, upload_url(client, kind), xml, filename, true) do
      {:ok, body, client}
    end
  end

  defp document(client, kind, path, opts) do
    with {:ok, %{size: size}} when size <= 5_000_000 <- File.stat(path),
         {:ok, xml} <- File.read(path) do
      expected = Keyword.get(opts, :expected_sha256)
      root = Xml.parse!(xml)
      issuer = Xml.value(root, ~w(Encabezado Emisor RNCEmisor))
      encf = Xml.value(root, ~w(Encabezado IdDoc eNCF))
      type = Xml.value(root, ~w(Encabezado IdDoc TipoeCF))
      amount = root |> Xml.value(~w(Encabezado Totales MontoTotal)) |> Rules.decimal!()
      small = type == "32" and Decimal.compare(amount, "250000.00") == :lt
      wanted_root = if kind == :ecf, do: "ECF", else: "RFCE"
      cond do
        expected && sha256(xml) != expected -> failure(:document, "Signed file checksum differs from manifest")
        elem(root, 0) != wanted_root -> failure(:document, "Wrong XML document root for reception service")
        issuer != client.issuer_rnc -> failure(:document, "Document issuer differs from configured RNC")
        not is_binary(encf) or not Regex.match?(~r/\AE[0-9]{12}\z/, encf) -> failure(:document, "Invalid eNCF")
        String.slice(encf, 1, 2) != type -> failure(:document, "eNCF and document type disagree")
        kind == :ecf and small -> failure(:document, "Low-amount type 32 requires RFCE reception and later portal upload")
        kind == :rfce and not small -> failure(:document, "RFCE requires type 32 below DOP 250000")
        Path.basename(path) != issuer <> encf <> ".xml" -> failure(:document, "Filename must be RNCEmisor + eNCF + .xml")
        true -> {:ok, xml, Path.basename(path), Xml.signature!(root)}
      end
    else
      _ -> failure(:document, "Cannot read signed XML or file exceeds 5 MB")
    end
  rescue
    _ -> failure(:document, "Invalid signed XML document")
  end

  defp seed_document(bytes) when is_binary(bytes) do
    root = Xml.parse!(bytes)
    if Xml.local(elem(root, 0)) == "SemillaModel" and
         is_binary(Xml.value(root, ["valor"])) and is_binary(Xml.value(root, ["fecha"])) do
      :ok
    else
      failure(:seed, "DGII did not return a SemillaModel XML document")
    end
  end
  defp seed_document(_), do: failure(:seed, "DGII did not return XML seed bytes")

  defp sign_seed(client, seed) do
    case Sign.sign(seed, client.p12_path, client.password, client.sign_options) do
      {:ok, signed} -> {:ok, signed}
      {:error, reason} -> failure(:authenticate, "Seed signing failed: #{reason}")
    end
  end

  defp session(client, body, signed) do
    with token when is_binary(token) and byte_size(token) > 0 <- body["token"],
         {:ok, expires, _} <- DateTime.from_iso8601(body["expira"] || ""),
         {:ok, issued, _} <- DateTime.from_iso8601(body["expedido"] || ""),
         true <- DateTime.compare(expires, DateTime.add(DateTime.utc_now(), 30, :second)) == :gt do
      signature = signed |> Xml.parse!() |> Xml.signature!()
      {:ok, %{client | token: token, expires_at: expires, issued_at: issued,
        certificate_sha256: signature.certificate_sha256}}
    else
      _ -> failure(:authenticate, "Authentication response has no valid token or UTC timestamps")
    end
  end

  defp ensure_token(%{token: token, expires_at: %DateTime{} = expires} = client) when is_binary(token) do
    if DateTime.compare(expires, DateTime.add(DateTime.utc_now(), 30, :second)) == :gt,
      do: {:ok, client}, else: authenticate(client)
  end
  defp ensure_token(client), do: authenticate(client)

  defp same_signer(client, signature) do
    if signature.certificate_sha256 == client.certificate_sha256,
      do: :ok, else: failure(:document, "Document signer differs from the authentication signing certificate")
  end

  defp upload(client, operation, url, bytes, filename, authenticated?) do
    request(client, operation, :post, url, [
      headers: if(authenticated?, do: headers(client), else: [{"accept", "application/json"}]),
      form_multipart: [{"xml", {bytes, filename: filename, content_type: "text/xml"}}]
    ])
  end

  defp request(client, operation, method, url, options) do
    # Never replay fiscal POSTs, forward credentials on redirects, or log HTTP bodies.
    options = Keyword.merge(options, [method: method, url: url, retry: false,
      redirect: false, decode_body: false, receive_timeout: client.receive_timeout,
      connect_options: [timeout: 10_000]])
    case Req.request(options) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        if operation == :seed, do: {:ok, body}, else: json_response(body, operation)
      {:ok, %{status: status, body: body}} ->
        {:error, %Error{operation: operation, http_status: status,
          message: "DGII #{operation} returned HTTP #{status}",
          details: if(operation in [:seed, :authenticate], do: nil, else: response_details(body)),
          uncertain: operation in [:ecf, :rfce]}}
      {:error, _} -> failure(operation, "DGII #{operation} transport failure", operation in [:ecf, :rfce])
    end
  rescue
    _ -> failure(operation, "DGII #{operation} request failed", operation in [:ecf, :rfce])
  end

  defp json_response(body, operation) do
    decoded = if is_map(body), do: {:ok, body}, else: Jason.decode(body)
    case decoded do
      {:ok, body} when is_map(body) -> {:ok, body}
      _ -> failure(operation, "DGII returned an invalid JSON response", operation in [:ecf, :rfce])
    end
  end

  defp response_details(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, value} when is_map(value) -> value
      _ -> "Non-JSON error response omitted"
    end
  end
  defp response_details(_), do: nil

  @doc "Classifies fiscal state without changing DGII's original response fields."
  def status(body, channel \\ :ecf) do
    state = case body["estado"] do
      value when is_binary(value) -> value |> String.downcase() |> String.replace(~r/[\s_-]+/u, "")
      _ -> ""
    end
    code = case body["codigo"] do
      value when is_binary(value) or is_integer(value) -> to_string(value)
      _ -> ""
    end
    cond do
      state == "aceptado" -> :accepted
      state == "aceptadocondicional" -> :accepted_conditional
      state == "rechazado" -> :rejected
      state == "enproceso" -> :pending
      state == "noencontrado" -> :not_found
      channel == :ecf -> code_status(code)
      true -> :unknown
    end
  end

  def accepted?(state), do: state in [:accepted, :accepted_conditional]
  defp code_status("1"), do: :accepted
  defp code_status("4"), do: :accepted_conditional
  defp code_status("2"), do: :rejected
  defp code_status("3"), do: :pending
  defp code_status("0"), do: :not_found
  defp code_status(_), do: :unknown

  defp headers(client), do: [{"accept", "application/json"}, {"authorization", "Bearer " <> client.token}]
  defp upload_url(client, :ecf), do: endpoint(client, :ecf) <> "/api/FacturasElectronicas"
  defp upload_url(client, :rfce), do: endpoint(client, :rfce) <> "/api/recepcion/ecf"
  defp endpoint(client, :rfce), do: "https://fc.dgii.gov.do/#{client.environment}/recepcionfc"
  defp endpoint(client, service) do
    path = %{auth: "Autenticacion", ecf: "Recepcion", result: "ConsultaResultado"}[service]
    environment = if client.environment == "certecf", do: "CerteCF", else: client.environment
    "https://ecf.dgii.gov.do/#{environment}/#{path}"
  end
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp failure(operation, message, uncertain \\ false), do: {:error, %Error{operation: operation, message: message, uncertain: uncertain}}
end
