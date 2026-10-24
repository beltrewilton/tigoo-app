defmodule TigooServerWeb.Plugs.ResolveTenant do
  @moduledoc "Resolves and validates the tenant subdomain for tenant-owned routes."

  import Plug.Conn

  alias TigooServer.{TenantContext, Tenants}

  @message "This page requires your organization's unique web address. Please contact your administrator for the correct link."

  def init(opts), do: opts

  def call(conn, opts) do
    case tenant_from_host(conn.host) do
      {:tenant, tenant} ->
        if Tenants.exists?(tenant) do
          TenantContext.put_tenant(tenant)

          conn
          |> assign(:tenant, tenant)
          |> maybe_put_session(tenant)
        else
          not_found(conn)
        end

      :base ->
        cond do
          Keyword.get(opts, :required, true) == false ->
            conn

          Keyword.get(opts, :base, :informational) == :not_found ->
            not_found(conn)

          true ->
            informational(conn)
        end

      :invalid ->
        if Keyword.get(opts, :required, true) == false and localhost_ip?(conn.host) do
          conn
        else
          not_found(conn)
        end
    end
  end

  def tenant_from_host(host) when is_binary(host) do
    host =
      host
      |> String.downcase()
      |> String.trim_trailing(".")

    base_host =
      TigooServerWeb.Endpoint.config(:url)
      |> Keyword.get(:host, "localhost")
      |> to_string()
      |> String.downcase()

    cond do
      host in [base_host, "localhost", "127.0.0.1"] ->
        :base

      String.ends_with?(host, ".localhost") ->
        host |> String.replace_suffix(".localhost", "") |> tenant_result()

      String.ends_with?(host, "." <> base_host) ->
        host |> String.replace_suffix("." <> base_host, "") |> tenant_result()

      true ->
        :invalid
    end
  end

  def tenant_from_host(_), do: :invalid

  defp localhost_ip?(host), do: host in ["::1", "[::1]"]

  defp tenant_result(tenant) do
    if Tenants.valid_identifier?(tenant), do: {:tenant, tenant}, else: :invalid
  end

  defp maybe_put_session(%{private: %{plug_session_fetch: _}} = conn, tenant),
    do: put_session(conn, :tenant, tenant)

  defp maybe_put_session(conn, _tenant), do: conn

  defp informational(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:not_found, TigooServerWeb.ErrorHTML.tenant_required_page(@message))
    |> halt()
  end

  defp not_found(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:not_found, TigooServerWeb.ErrorHTML.not_found_page())
    |> halt()
  end
end
