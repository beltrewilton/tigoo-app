defmodule TigooServerWeb.FeAuthenticationController do
  use TigooServerWeb, :controller

  require Logger

  import Saxy.XML, only: [element: 3]

  alias TigooServer.FeAuthentication

  def semilla(conn, _params) do
    case FeAuthentication.new_seed() do
      {:ok, seed} ->
        Logger.info("FE authentication stage=seed_issue result=ok host=#{inspect(conn.host)}")
        respond(conn, "SemillaModel", seed, [:valor, :fecha])
      {:error, :seed_capacity} -> error(conn, :service_unavailable, "Servicio temporalmente no disponible")
    end
  end

  def validacioncertificado(conn, %{"xml" => %Plug.Upload{path: path}}) do
    Logger.info("FE authentication stage=upload result=received host=#{inspect(conn.host)}")
    with {:ok, xml} <- read_upload(path),
         {:ok, response} <- FeAuthentication.validate_certificate(xml) do
      Logger.info("FE authentication stage=token_issue result=ok")
      respond(conn, "RespuestaAutenticacion", response, [:token, :expira, :expedido])
    else
      {:error, :verifier_unavailable} ->
        error(conn, :service_unavailable, "Verificador de certificados no configurado o no disponible")

      {:error, :invalid_seed} ->
        Logger.warning("FE authentication stage=seed_consume result=rejected reason=unknown_expired_or_used")
        error(conn, :unauthorized, "Semilla desconocida, vencida o utilizada")

      _ ->
        error(conn, :bad_request, "XML o firma de certificado no valido")
    end
  end

  def validacioncertificado(conn, _params) do
    Logger.warning("FE authentication stage=upload result=rejected reason=missing_multipart_xml host=#{inspect(conn.host)}")
    error(conn, :bad_request, "Se requiere el archivo XML firmado en el campo xml (multipart/form-data)")
  end

  defp read_upload(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size <= 65_536 ->
        case File.read(path) do
          {:ok, xml} ->
            Logger.info("FE authentication stage=upload_read result=ok bytes=#{size}")
            {:ok, xml}
          {:error, reason} = error ->
            Logger.warning("FE authentication stage=upload_read result=rejected reason=#{inspect(reason)}")
            error
        end
      {:ok, %{size: size}} ->
        Logger.warning("FE authentication stage=upload_size result=rejected bytes=#{size} limit_bytes=65536")
        {:error, :too_large}
      {:error, reason} = error ->
        Logger.warning("FE authentication stage=upload_stat result=rejected reason=#{inspect(reason)}")
        error
    end
  end

  defp error(conn, status, message) do
    Logger.warning("FE authentication stage=http_response status=#{status}")
    conn |> put_status(status) |> respond("ErrorAutenticacion", %{mensaje: message}, [:mensaje])
  end

  defp respond(conn, root, data, fields) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
      |> put_resp_header("vary", "Accept")

    case get_format(conn) do
      "json" -> json(conn, data)
      "xml" -> xml(conn, root, data, fields)
    end
  end

  defp xml(conn, root, data, fields) do
    document =
      element(root, [], Enum.map(fields, fn field -> element(Atom.to_string(field), [], Map.fetch!(data, field)) end))

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(conn.status || 200, Saxy.encode!(document, version: "1.0", encoding: "UTF-8"))
  end
end
