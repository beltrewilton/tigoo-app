defmodule TigooServerWeb.Plugs.PutTenantFromScope do
  @moduledoc """
  Sets the authenticated user's Triplex tenant in the request process.
  """

  import Plug.Conn

  alias TigooServer.TenantContext

  def init(opts), do: opts

  def call(%{assigns: %{tenant: tenant, current_scope: %{tenant: scope_tenant}}} = conn, _opts)
      when is_binary(tenant) and is_binary(scope_tenant) and tenant != scope_tenant do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(:unauthorized, ~s({"error":"authentication required"}))
    |> halt()
  end

  def call(%{assigns: %{tenant: tenant, current_scope: %{tenant: tenant}}} = conn, _opts)
      when is_binary(tenant) and tenant != "" do
    TenantContext.put_tenant(tenant)
    conn
  end

  def call(%{assigns: %{tenant: _tenant}} = conn, _opts), do: conn

  def call(%{assigns: %{current_scope: %{user: %{tenant: tenant}}}} = conn, _opts)
      when is_binary(tenant) and tenant != "" do
    TenantContext.put_tenant(tenant)
    conn
  end

  def call(conn, _opts), do: conn
end
