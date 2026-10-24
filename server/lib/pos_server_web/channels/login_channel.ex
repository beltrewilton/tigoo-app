defmodule TigooServerWeb.LoginChannel do
  use TigooServerWeb, :channel

  alias TigooServer.Authentication

  def join("login:" <> attempt_id, _payload, %{assigns: %{login_attempt_id: attempt_id}} = socket) do
    case Authentication.login_attempt_result(attempt_id) do
      {:ok, payload} -> {:ok, payload, socket}
      {:error, _} -> {:error, %{reason: "login_attempt_expired"}}
    end
  end

  def join(_, _, _), do: {:error, %{reason: "unauthorized_login_attempt"}}
end
