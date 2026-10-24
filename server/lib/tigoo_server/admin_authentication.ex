defmodule TigooServer.AdminAuthentication do
  @moduledoc "Server-side authentication for the Phoenix admin area."

  @spec authenticate(term(), term()) :: :ok | :error
  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    credentials = Application.get_env(:tigoo_server, :admin_auth, [])
    expected_username = Keyword.get(credentials, :username)
    expected_password = Keyword.get(credentials, :password)

    with true <- is_binary(expected_username),
         true <- is_binary(expected_password),
         username_matches? = secure_compare(expected_username, username),
         password_matches? = secure_compare(expected_password, password),
         true <- username_matches? and password_matches? do
      :ok
    else
      _ -> :error
    end
  end

  def authenticate(_username, _password), do: :error

  defp secure_compare(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  defp secure_compare(_left, _right), do: false
end
