defmodule TigooServerWeb.TauriAuthController do
  use TigooServerWeb, :controller

  alias TigooServer.Authentication

  def create_attempt(conn, %{"platform" => platform}) when platform in ["desktop", "mobile"] do
    case Authentication.create_tauri_login_attempt(platform) do
      {:ok, attempt} ->
        json(conn, attempt)

      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "could not create login attempt"})
    end
  end

  def create_attempt(conn, _params),
    do: conn |> put_status(:bad_request) |> json(%{error: "unsupported platform"})

  def exchange(conn, %{"code" => code}) when is_binary(code) do
    with {:ok, user} <- Authentication.consume_tauri_handoff(code),
         {:ok, token, scope} <- Authentication.log_in_user(user) do
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
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid or expired authentication code"})
    end
  end

  def exchange(conn, _params),
    do: conn |> put_status(:bad_request) |> json(%{error: "authentication code is required"})
end
