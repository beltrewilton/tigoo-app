defmodule TigooServerWeb.UserSocket do
  use Phoenix.Socket

  channel "system:*", TigooServerWeb.SystemChannel
  channel "inventory:*", TigooServerWeb.SystemChannel
  channel "print-relay:*", TigooServerWeb.SystemChannel
  channel "login:*", TigooServerWeb.LoginChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case TigooServer.Authentication.authenticate(token) do
      {:ok, scope} ->
        {:ok,
         assign(socket,
           scope: scope,
           tenant: scope.tenant,
           session_expires_at: System.system_time(:second) + 86_400
         )}

      {:error, _} ->
        :error
    end
  end

  def connect(%{"login_attempt_id" => id, "login_attempt_token" => token}, socket, _connect_info) do
    case TigooServer.Authentication.authenticate_tauri_login_attempt(id, token) do
      {:ok, _attempt} -> {:ok, assign(socket, login_attempt_id: id)}
      {:error, _} -> :error
    end
  end

  def connect(_, _socket, _connect_info), do: :error

  @impl true
  def id(_socket), do: nil
end
