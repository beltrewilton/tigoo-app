defmodule TigooServer.Fe.Postulacion do
  @moduledoc "Signs the DGII application using the authenticated tenant's identity."
  alias TigooServer.{Sign, Fe.Credentials}

  def sign(tenant, xml) when is_binary(xml) and byte_size(xml) <= 5_000_000 do
    with {:ok, {"Postulacion", _, _} = document} <- Saxy.SimpleForm.parse_string(xml,
           expand_entity: {Sign, :reject_entity, []}),
         :ok <- validate_software_version(document),
         {:ok, identity} <- Credentials.for_tenant(tenant) do
      Sign.sign(xml, identity.p12_path, identity.password)
    else
      {:error, :invalid_software_version} -> {:error, :invalid_software_version}
      {:error, :signing_identity_unavailable} -> {:error, :signing_identity_unavailable}
      _ -> {:error, :invalid_postulacion}
    end
  rescue
    _ -> {:error, :invalid_postulacion}
  end

  def sign(_, _), do: {:error, :invalid_postulacion}

  # DGII declares VersionSoftware as xs:double, rather than a semantic version.
  # Validate the source without rewriting any values supplied by the applicant.
  defp validate_software_version({"VersionSoftware", _, children}) do
    if Enum.all?(children, &is_binary/1) and
         Regex.match?(~r/\A(?:[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?|INF|-INF|NaN)\z/,
           children |> Enum.join() |> String.trim()) do
      :ok
    else
      {:error, :invalid_software_version}
    end
  end

  defp validate_software_version({_, _, children}) do
    Enum.reduce_while(children, :ok, fn child, :ok ->
      case validate_software_version(child) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_software_version(_), do: :ok
end
