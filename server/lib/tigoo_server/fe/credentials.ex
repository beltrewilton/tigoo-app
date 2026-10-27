defmodule TigooServer.Fe.Credentials do
  @moduledoc "Reads a signing password without shell evaluation or logging its contents."

  def for_tenant(tenant) do
    with true <- TigooServer.Tenants.valid_identifier?(tenant),
         root when is_binary(root) <- Application.get_env(:tigoo_server, :fe_receivers_directory),
         directory <- Path.join(root, tenant),
         {:ok, files} <- File.ls(directory),
         [filename] <- Enum.filter(files, &(String.downcase(Path.extname(&1)) == ".p12")),
         path <- Path.join(directory, filename),
         true <- File.regular?(path),
         credentials_file <- Path.join(directory, "credentials.txt"),
         password <- password!(credentials_file: credentials_file) do
      {:ok, %{p12_path: path, credentials_file: credentials_file, password: password}}
    else
      _ -> {:error, :signing_identity_unavailable}
    end
  rescue
    _ -> {:error, :signing_identity_unavailable}
  end

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
