defmodule TigooServerWeb.FeAuthenticationController do
  use TigooServerWeb, :controller

  import Saxy.XML, only: [element: 3]

  alias TigooServer.FeAuthentication

  def semilla(conn, _params) do
    case FeAuthentication.new_seed() do
      {:ok, seed} -> respond(conn, "SemillaModel", seed, [:valor, :fecha])
      {:error, :seed_capacity} -> error(conn, :service_unavailable, "Servicio temporalmente no disponible")
    end
  end

  def validacioncertificado(conn, %{"xml" => %Plug.Upload{path: path}}) do
    with {:ok, %{size: size}} when size <= 65_536 <- File.stat(path),
         {:ok, xml} <- File.read(path),
         {:ok, response} <- FeAuthentication.validate_certificate(xml) do
      respond(conn, "RespuestaAutenticacion", response, [:token, :expira, :expedido])
    else
      {:error, :verifier_unavailable} ->
        error(conn, :service_unavailable, "Verificador de certificados no configurado o no disponible")

      {:error, :invalid_seed} ->
        error(conn, :unauthorized, "Semilla desconocida, vencida o utilizada")

      _ ->
        error(conn, :bad_request, "XML o firma de certificado no valido")
    end
  end

  def validacioncertificado(conn, _params) do
    error(conn, :bad_request, "Se requiere el archivo XML firmado en el campo xml (multipart/form-data)")
  end

  defp error(conn, status, message) do
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
