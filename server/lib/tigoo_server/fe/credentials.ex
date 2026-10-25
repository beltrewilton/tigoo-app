defmodule TigooServer.Fe.Credentials do
  @moduledoc "Reads a signing password without shell evaluation or logging its contents."

  def password!(opts) do
    password = case Keyword.fetch(opts, :password) do
      {:ok, password} -> password
      :error ->
        path = Keyword.get(opts, :credentials_file) || raise(ArgumentError, "Missing credentials_file or password")
        case Regex.scan(~r/^[\t ]*Password[\t ]*[:=][\t ]*([^\r\n]+)\r?$/mi, File.read!(path), capture: :all_but_first) do
          [[value]] -> value |> String.trim() |> String.trim("\"") |> String.trim("'")
          _ -> raise ArgumentError, "Expected exactly one Password field in credentials file"
        end
    end
    if not is_binary(password) or password == "" or String.contains?(password, ["\0", "\r", "\n"]) do
      raise ArgumentError, "Invalid signing password"
    end
    password
  end
end
