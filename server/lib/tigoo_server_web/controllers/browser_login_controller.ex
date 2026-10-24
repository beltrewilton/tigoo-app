defmodule TigooServerWeb.BrowserLoginController do
  use TigooServerWeb, :controller

  alias TigooServer.{Authentication, TenantContext}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.InventoryContext

  def create(conn, %{"token" => token, "store_id" => store_id}) do
    with {:ok, scope} <- Authentication.authenticate(token),
         _ <- TenantContext.put_tenant(scope.tenant),
         {store_id, ""} <- Integer.parse(to_string(store_id)),
         {:ok, _} <- InventoryContext.authorize_store(scope, store_id) do
      conn
      |> configure_session(renew: true)
      |> put_session(:user_token, token)
      |> put_session(:store_id, store_id)
      |> json(%{redirect_to: landing_path(scope)})
    else
      _ -> conn |> put_status(:unauthorized) |> json(%{error: "invalid login session"})
    end
  end

  def create(conn, _params),
    do: conn |> put_status(:bad_request) |> json(%{error: "invalid login session"})

  def delete(conn, _params) do
    conn
    |> clear_browser_auth_session()
    |> redirect(to: ~p"/pos/login")
  end

  defp clear_browser_auth_session(conn) do
    conn
    |> delete_session(:user_token)
    |> delete_session(:store_id)
    |> delete_session(:tenant)
    |> delete_session(:google_oauth_state)
    |> delete_session(:admin_authenticated)
    |> configure_session(drop: true)
  end

  defp landing_path(scope) do
    cond do
      Scope.admin?(scope) -> ~p"/pos/dashboard"
      Scope.allowed?(scope, "dashboard.view") -> ~p"/pos/dashboard"
      true -> ~p"/pos"
    end
  end
end
