defmodule TigooServerWeb.FeCommercialApprovalController do
  use TigooServerWeb, :controller
  alias TigooServer.FeApprovalReception
  alias TigooServerWeb.FeRequest

  def create(conn, params) do
    conn = conn |> put_resp_header("cache-control", "no-store") |> put_resp_header("pragma", "no-cache")

    with {:ok, tenant, xml, identity} <- FeRequest.read(conn, params),
         :ok <- FeApprovalReception.receive_approval(tenant, xml, identity) do
      text(conn, "OK")
    else
      {:error, :invalid_token} ->
        conn |> put_resp_header("www-authenticate", "Bearer error=\"invalid_token\"")
        |> put_status(:unauthorized) |> text("Token de autenticacion ausente, invalido o vencido")
      {:error, :invalid_tenant} ->
        conn |> put_status(:not_found) |> text("Emisor no encontrado para este host")
      {:error, :too_large} ->
        conn |> put_status(:request_entity_too_large) |> text("El XML excede el limite de 5 MB")
      {:error, reason} when reason in [:verifier_unavailable, :reception_unavailable] ->
        conn |> put_status(:service_unavailable) |> text("Recepcion o validacion no disponible")
      {:error, reason} when reason in [:invalid_xml, :invalid_schema, :invalid_signature, :wrong_issuer] ->
        conn |> put_status(:bad_request) |> text("Aprobacion comercial no valida")
    end
  end
end
