defmodule TigooServerWeb.AuthController do
  use TigooServerWeb, :controller

  alias TigooServer.Authentication

  def login(conn, params) do
    case Authentication.login(params, conn.assigns[:tenant]) do
      {:ok, token, scope} ->
        json(conn, %{
          token: token,
          user: %{
            type: scope.actor,
            id: scope.actor_id,
            login: scope.login,
            pic: scope.pic,
            tenant: scope.tenant,
            store_ids: scope.store_ids,
            scopes: scope.scopes
          }
        })

      {:error, :invalid_credentials} ->
        conn |> put_status(:unauthorized) |> json(%{error: "invalid credentials"})
    end
  end
end
