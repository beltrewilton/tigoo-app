defmodule TigooServer.Fe.Postulacion do
  @moduledoc "Signs the DGII application using the authenticated tenant's identity."
  alias TigooServer.{Sign, Fe.Credentials}

  def sign(tenant, xml) when is_binary(xml) and byte_size(xml) <= 5_000_000 do
    with {:ok, {"Postulacion", _, _}} <- Saxy.SimpleForm.parse_string(xml,
           expand_entity: {Sign, :reject_entity, []}),
         {:ok, identity} <- Credentials.for_tenant(tenant) do
      Sign.sign(xml, identity.p12_path, identity.password)
    else
      {:error, :signing_identity_unavailable} -> {:error, :signing_identity_unavailable}
      _ -> {:error, :invalid_postulacion}
    end
  rescue
    _ -> {:error, :invalid_postulacion}
  end

  def sign(_, _), do: {:error, :invalid_postulacion}
end
