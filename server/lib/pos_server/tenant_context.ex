defmodule PosServer.TenantContext do
  @moduledoc """
  Holds the authenticated request's Triplex tenant for the current process.

  Tenant data must always be read through `tenant!/0` and passed to Ecto as a
  schema prefix. It is deliberately process-local so concurrent requests
  cannot share a tenant.
  """

  @key :current_tenant

  @spec put_tenant(String.t()) :: String.t()
  def put_tenant(tenant) when is_binary(tenant) do
    Process.put(@key, tenant)
    tenant
  end

  @spec get_tenant() :: String.t() | nil
  def get_tenant, do: Process.get(@key)

  @doc "Clears the tenant context for the current process."
  def clear_tenant, do: Process.delete(@key)

  @spec tenant!() :: String.t()
  def tenant! do
    get_tenant() || raise "tenant context is not set"
  end
end
