defmodule TigooServerWeb.GoogleAuthController do
  use TigooServerWeb, :controller

  alias TigooServer.{Accounts, Authentication}
  alias TigooServer.Accounts.Scope

  @google_authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @google_user_info_url "https://www.googleapis.com/oauth2/v3/userinfo"

  def redirect_to(conn, _params) do
    state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    conn
    |> put_session(:google_oauth_state, state)
    |> redirect(external: google_auth_url(state))
  end

  def tauri_redirect_to(conn, %{"platform" => platform, "attempt_id" => attempt_id})
      when platform in ["desktop", "mobile"] do
    if Authentication.valid_tauri_login_attempt?(attempt_id) do
      state = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

      conn
      |> put_session(:google_oauth_state, %{
        value: state,
        client: "tauri",
        platform: platform,
        attempt_id: attempt_id
      })
      |> redirect(external: google_auth_url(state))
    else
      conn |> put_status(:unauthorized) |> text("Invalid or expired Tauri login attempt")
    end
  end

  def tauri_redirect_to(conn, _params),
    do: conn |> put_status(:bad_request) |> text("Unsupported Tauri platform")

  # Compatibility entry point for the helper URL used by edoc. Keep the OAuth
  # work in this controller so the callback has one state-aware implementation.
  def helper(conn, _params), do: redirect(conn, to: ~p"/google_auth_url")

  def logout(conn, _params) do
    conn
    |> delete_session(:user_token)
    |> delete_session(:store_id)
    |> delete_session(:tenant)
    |> delete_session(:google_oauth_state)
    |> delete_session(:admin_authenticated)
    |> configure_session(drop: true)
    |> redirect(to: ~p"/")
  end

  def callback(conn, %{"code" => code, "state" => state}) do
    with :ok <- verify_state(conn, state),
         {:ok, token_map} <- exchange_code_for_token(code),
         {:ok, user_info} <- fetch_user_info(token_map["access_token"]),
         {:ok, user} <- upsert_google_user(conn, user_info) do
      finish_google_sign_in(conn, user)
    else
      {:error, reason} -> google_error(conn, reason)
      _ -> google_error(conn, :google_sign_in_failed)
    end
  end

  def callback(conn, _params), do: google_error(conn, :google_sign_in_cancelled)

  def google_auth_url(state) when is_binary(state) do
    %{client_id: client_id, redirect_uri: redirect_uri} = google_config!()

    query =
      URI.encode_query(%{
        "access_type" => "offline",
        "client_id" => client_id,
        "prompt" => "consent",
        "redirect_uri" => redirect_uri,
        "response_type" => "code",
        "scope" => "openid email profile",
        "state" => state
      })

    @google_authorize_url <> "?" <> query
  end

  defp exchange_code_for_token(code) do
    %{client_id: client_id, client_secret: client_secret, redirect_uri: redirect_uri} =
      google_config!()

    case Req.post(@google_token_url,
           form: %{
             "client_id" => client_id,
             "client_secret" => client_secret,
             "code" => code,
             "grant_type" => "authorization_code",
             "redirect_uri" => redirect_uri
           }
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:google_token_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_user_info(access_token) when is_binary(access_token) do
    case Req.get(@google_user_info_url, headers: [{"authorization", "Bearer #{access_token}"}]) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:google_user_info_error, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_user_info(_), do: {:error, :missing_google_access_token}

  defp verify_state(conn, state) when is_binary(state) do
    case get_session(conn, :google_oauth_state) do
      expected when is_binary(expected) and byte_size(expected) == byte_size(state) ->
        if Plug.Crypto.secure_compare(expected, state),
          do: :ok,
          else: {:error, :invalid_google_oauth_state}

      %{value: expected} when is_binary(expected) and byte_size(expected) == byte_size(state) ->
        if Plug.Crypto.secure_compare(expected, state),
          do: :ok,
          else: {:error, :invalid_google_oauth_state}

      _ ->
        {:error, :invalid_google_oauth_state}
    end
  end

  defp verify_state(_conn, _state), do: {:error, :invalid_google_oauth_state}

  defp google_config! do
    config = Application.get_env(:tigoo_server, :google_oauth, [])
    client_id = Keyword.fetch!(config, :client_id)
    client_secret = Keyword.fetch!(config, :client_secret)

    if is_binary(client_id) and client_id != "" and is_binary(client_secret) and
         client_secret != "" do
      %{
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: google_redirect_uri(config)
      }
    else
      raise "GOOGLE_CLIENT and GOOGLE_KEY must be configured to use Google sign-in"
    end
  end

  defp google_redirect_uri(config) do
    case Keyword.get(config, :redirect_uri) do
      uri when is_binary(uri) and uri != "" -> uri
      _ -> TigooServerWeb.Endpoint.url() <> "/auth/google/callback"
    end
  end

  defp upsert_google_user(conn, user_info) do
    case get_session(conn, :google_oauth_state) do
      %{client: "tauri"} -> Accounts.upsert_tauri_user_from_google(user_info)
      _ -> Accounts.upsert_user_from_google(user_info)
    end
  end

  defp finish_google_sign_in(conn, user) do
    case get_session(conn, :google_oauth_state) do
      %{client: "tauri", attempt_id: attempt_id} ->
        case Authentication.complete_tauri_login_attempt(attempt_id, user) do
          {:ok, payload} ->
            TigooServerWeb.Endpoint.broadcast("login:" <> attempt_id, "login_result", payload)
            tauri_result_page(conn, :success)

          {:error, _} ->
            tauri_result_page(conn, :error)
        end

      _ ->
        with {:ok, session_token, scope} <- Authentication.log_in_user(user) do
          conn
          |> delete_session(:google_oauth_state)
          |> configure_session(renew: true)
          |> put_session(:user_token, session_token)
          |> put_flash(:info, "Sesión iniciada con Google.")
          |> redirect(external: landing_url(scope))
        end
    end
  end

  defp landing_url(scope) do
    path =
      cond do
        Scope.admin?(scope) -> ~p"/pos/dashboard"
        Scope.allowed?(scope, "dashboard.view") -> ~p"/pos/dashboard"
        true -> ~p"/pos"
      end

    tenant_url(scope, path)
  end

  defp tenant_url(%Scope{tenant: tenant}, path) when is_binary(tenant) and tenant != "" do
    url = TigooServerWeb.Endpoint.config(:url)
    host = url |> Keyword.get(:host, "localhost") |> to_string()
    scheme = url |> Keyword.get(:scheme, "https") |> to_string()

    URI.to_string(%URI{scheme: scheme, host: "#{tenant}.#{host}", path: path})
  end

  defp tenant_url(_scope, path), do: path

  defp google_error(conn, _reason) do
    case get_session(conn, :google_oauth_state) do
      %{client: "tauri", attempt_id: attempt_id} ->
        case Authentication.fail_tauri_login_attempt(attempt_id, "google_sign_in_failed") do
          {:ok, payload} ->
            TigooServerWeb.Endpoint.broadcast("login:" <> attempt_id, "login_result", payload)

          _ ->
            :ok
        end

        tauri_result_page(conn, :error)

      _ ->
        conn
        |> delete_session(:google_oauth_state)
        |> put_flash(:error, "No se pudo iniciar sesión con Google. Inténtalo de nuevo.")
        |> redirect(to: ~p"/")
    end
  end

  defp tauri_result_page(conn, :success) do
    conn
    |> delete_session(:google_oauth_state)
    |> configure_session(drop: true)
    |> put_resp_content_type("text/html")
    |> send_resp(
      200,
      "<!doctype html><html><head><meta charset=\"utf-8\"><title>Signed in</title></head><body><main><h1>You’re signed in to tigoo</h1><p>You can close this page and return to the app.</p></main></body></html>"
    )
  end

  defp tauri_result_page(conn, :error) do
    conn
    |> delete_session(:google_oauth_state)
    |> configure_session(drop: true)
    |> put_resp_content_type("text/html")
    |> send_resp(
      400,
      "<!doctype html><html><head><meta charset=\"utf-8\"><title>Sign-in failed</title></head><body><main><h1>Sign-in couldn’t be completed</h1><p>You can close this page and try again from tigoo.</p></main></body></html>"
    )
  end
end
