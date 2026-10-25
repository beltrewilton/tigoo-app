defmodule TigooServerWeb.FeReceptionController do
  use TigooServerWeb, :controller

  alias TigooServer.{FeAuthentication, FeReception, TenantContext, Tenants}
  alias TigooServerWeb.Plugs.ResolveTenant

  def create(conn, params) do
    with {:ok, identity} <- authenticate(conn),
         {:ok, tenant} <- tenant(conn.host),
         {:ok, xml} <- upload(params),
         {:ok, acknowledgement} <- FeReception.receive_ecf(tenant, xml, identity) do
      conn = headers(conn)

      case get_format(conn) do
        "json" -> json(conn, %{"ARECF" => %{"DetalleAcusedeRecibo" => acknowledgement.details}, "xml" => acknowledgement.xml})
        "xml" -> conn |> put_resp_content_type("application/xml") |> send_resp(200, acknowledgement.xml)
      end
    else
      {:error, :invalid_token} ->
        conn |> put_resp_header("www-authenticate", "Bearer error=\"invalid_token\"")
        |> error(:unauthorized, "Token de autenticacion ausente, invalido o vencido")
      {:error, :invalid_tenant} -> error(conn, :not_found, "Receptor no encontrado para este host")
      {:error, :too_large} -> error(conn, :request_entity_too_large, "El XML excede el limite de 5 MB")
      {:error, :invalid_xml} -> error(conn, :bad_request, "Se requiere un e-CF XML en el campo xml (multipart/form-data)")
      {:error, reason} when reason in [:verifier_unavailable, :reception_unavailable] ->
        error(conn, :service_unavailable, "Recepcion o firma del receptor no disponible")
    end
  end

  defp authenticate(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         [_, token] <- Regex.run(~r/\ABearer[ \t]+([^\s]+)\z/i, header) do
      FeAuthentication.verify_token(token)
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp tenant(host) do
    with {:tenant, tenant} <- ResolveTenant.tenant_from_host(host),
         true <- Tenants.exists?(tenant) do
      TenantContext.put_tenant(tenant)
      {:ok, tenant}
    else
      _ -> {:error, :invalid_tenant}
    end
  end

  defp upload(%{"xml" => %Plug.Upload{path: path}}) do
    with {:ok, %{size: size}} <- File.stat(path),
         true <- size <= 5_000_000,
         {:ok, xml} <- File.read(path) do
      {:ok, xml}
    else
      false -> {:error, :too_large}
      _ -> {:error, :invalid_xml}
    end
  end

  defp upload(_), do: {:error, :invalid_xml}

  defp headers(conn) do
    conn |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache") |> put_resp_header("vary", "Accept")
  end

  defp error(conn, status, message) do
    conn = conn |> headers() |> put_status(status)

    case get_format(conn) do
      "json" -> json(conn, %{mensaje: message})
      "xml" ->
        xml = Saxy.XML.element("ErrorRecepcion", [], [
          Saxy.XML.element("mensaje", [], Saxy.XML.characters(message))
        ]) |> Saxy.encode!(version: "1.0", encoding: "UTF-8")

        conn |> put_resp_content_type("application/xml") |> send_resp(conn.status, xml)
    end
  end
end
