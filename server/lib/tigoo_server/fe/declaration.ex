defmodule TigooServer.Fe.Declaration do
  @moduledoc """
  Signs DGII declarations using the identity configured for a deployment tenant.

  No database access or HTTP submission is performed. Signed bytes must be kept
  unchanged when saving or uploading the declaration.
  """

  alias TigooServer.Fe.Credentials
  alias TigooServer.Sign

  @max_bytes 5_000_000

  @doc "Returns a signed DeclaracionJurada XML using p12_companies/[tenant]."
  def sign(tenant, xml) when is_binary(xml) and byte_size(xml) <= @max_bytes do
    with :ok <- declaration(xml),
         {:ok, identity} <- Credentials.for_tenant(tenant) do
      Sign.sign(xml, identity.p12_path, identity.password)
    end
  end

  def sign(_, _), do: {:error, :invalid_xml}

  @doc "Signs a declaration file and creates a new output without overwriting files."
  def sign_file(tenant, input_path, output_path) do
    with {:ok, %{size: size}} when size <= @max_bytes <- File.stat(input_path),
         {:ok, xml} <- File.read(input_path),
         {:ok, signed} <- sign(tenant, xml) do
      File.write(output_path, signed, [:exclusive])
    else
      {:ok, _stat} -> {:error, :invalid_xml}
      error -> error
    end
  end

  defp declaration(xml) do
    if String.valid?(xml) and not String.contains?(xml, ["<!DOCTYPE", "<!ENTITY", "\0"]) and
         not Regex.match?(~r/<\?(?!xml\s)/, xml) do
      case Saxy.SimpleForm.parse_string(xml, expand_entity: {Sign, :reject_entity, []}) do
        {:ok, {"DeclaracionJurada", _, _}} -> :ok
        _ -> {:error, :invalid_xml}
      end
    else
      {:error, :invalid_xml}
    end
  rescue
    _ -> {:error, :invalid_xml}
  end
end
