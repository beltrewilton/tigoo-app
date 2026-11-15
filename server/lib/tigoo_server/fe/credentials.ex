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

  @doc "Installs the two uploaded identity files in the authenticated tenant's directory."
  def upload_for_tenant(tenant, certificate_path, filename, credentials_path) do
    with true <- TigooServer.Tenants.valid_identifier?(tenant),
         root when is_binary(root) <- Application.get_env(:tigoo_server, :fe_receivers_directory),
         true <- Path.extname(String.downcase(filename)) == ".p12",
         password <- password!(credentials_file: credentials_path),
         {:ok, certificate} <- File.read(certificate_path),
         true <- byte_size(certificate) in 1..5_000_000,
         {:ok, credentials} <- File.read(credentials_path),
         true <- byte_size(credentials) <= 64_000,
         # Validate the certificate and password together before replacing any files.
         {:ok, _} <- TigooServer.Sign.sign("<Postulacion><RNC>0</RNC></Postulacion>", certificate_path, password),
         directory <- Path.join(root, tenant),
         :ok <- File.mkdir_p(directory),
         {:ok, files} <- File.ls(directory),
         certificates <- Enum.filter(files, &(String.downcase(Path.extname(&1)) == ".p12")),
         true <- length(certificates) <= 1 do
      # Reuse the existing certificate name so the directory always has one .p12.
      name = List.first(certificates) || Path.basename(filename)
      save_identity(directory, name, certificate, credentials)
    else
      _ -> {:error, :invalid_signing_identity}
    end
  rescue
    _ -> {:error, :invalid_signing_identity}
  end

  defp save_identity(directory, name, certificate, credentials) do
    suffix = ".upload-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    certificate_temp = Path.join(directory, suffix <> ".certificate")
    credentials_temp = Path.join(directory, suffix <> ".credentials")
    certificate_path = Path.join(directory, name)
    credentials_path = Path.join(directory, "credentials.txt")
    previous_certificate = File.read(certificate_path)

    try do
      with :ok <- private_write(certificate_temp, certificate),
           :ok <- private_write(credentials_temp, credentials),
           :ok <- File.rename(certificate_temp, certificate_path) do
        case File.rename(credentials_temp, credentials_path) do
          :ok -> :ok
          error ->
            case previous_certificate do
              {:ok, bytes} ->
                with :ok <- private_write(certificate_temp, bytes),
                  do: File.rename(certificate_temp, certificate_path)
              _ -> File.rm(certificate_path)
            end
            error
        end
      end
    after
      File.rm(certificate_temp)
      File.rm(credentials_temp)
    end
  end

  defp private_write(path, bytes) do
    with {:ok, file} <- File.open(path, [:write, :binary, :exclusive]) do
      try do
        with :ok <- File.chmod(path, 0o600), do: IO.binwrite(file, bytes)
      after
        File.close(file)
      end
    end
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
