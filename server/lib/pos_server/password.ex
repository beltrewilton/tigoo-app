defmodule TigooServer.Password do
  @moduledoc false

  # Retaily uses Passlib's default bcrypt configuration: bcrypt revision 2b
  # with 12 log rounds. bcrypt_elixir reads and verifies that same standard
  # format, including Retaily's existing `$2b$12$...` hashes.
  @bcrypt_log_rounds 12

  def hash(password) when is_binary(password),
    do: Bcrypt.hash_pwd_salt(password, log_rounds: @bcrypt_log_rounds)

  def verify(password, hash) when is_binary(password) and is_binary(hash),
    do: Bcrypt.verify_pass(password, hash)

  def verify(_, _), do: false
end
