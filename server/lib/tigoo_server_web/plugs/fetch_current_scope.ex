defmodule TigooServerWeb.Plugs.FetchCurrentScope do
  @moduledoc "Loads the authenticated admin or employee from a bearer token."

  import Plug.Conn

  alias TigooServer.Authentication

  def init(opts), do: opts

  def call(conn, _opts) do
    with token when is_binary(token) <- authorization_token(conn) || session_token(conn),
         {:ok, scope} <- Authentication.authenticate(token) do
      assign(conn, :current_scope, scope)
    else
      _ -> conn
    end
  end

  defp authorization_token(conn) do
    case Plug.Conn.get_req_header(conn, "authorization")
         |> List.first()
         |> to_string()
         |> String.split(" ", parts: 2) do
      ["Bearer", token] -> token
      _ -> nil
    end
  end

  defp session_token(%{private: %{plug_session_fetch: _}} = conn),
    do: Plug.Conn.get_session(conn, :user_token)

  defp session_token(_conn), do: nil
end
