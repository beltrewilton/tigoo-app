defmodule TigooServerWeb.FeRequest do
  @moduledoc false
  import Plug.Conn, only: [get_req_header: 2]
  alias TigooServer.{FeAuthentication, TenantContext, Tenants}
  alias TigooServerWeb.Plugs.ResolveTenant

  def read(conn, params) do
    with {:ok, identity} <- authenticate(conn),
         {:ok, tenant} <- tenant(conn.host),
         {:ok, xml} <- upload(params) do
      {:ok, tenant, xml, identity}
    end
  end

  defp authenticate(conn) do
    with [header] <- get_req_header(conn, "authorization"),
         [_, token] <- Regex.run(~r/\ABearer[ \t]+([^\s]+)\z/i, header) do
      FeAuthentication.verify_token(token)
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp tenant(host) do
    with {:tenant, tenant} <- ResolveTenant.tenant_from_host(host),
         true <- Tenants.exists?(tenant) do
      TenantContext.put_tenant(tenant)
      {:ok, tenant}
    else
      _ -> {:error, :invalid_tenant}
    end
  end

  defp upload(%{"xml" => %Plug.Upload{path: path}}) do
    with {:ok, %{size: size}} <- File.stat(path),
         true <- size <= 5_000_000,
         {:ok, xml} <- File.read(path) do
      {:ok, xml}
    else
      false -> {:error, :too_large}
      _ -> {:error, :invalid_xml}
    end
  end

  defp upload(_), do: {:error, :invalid_xml}
end
