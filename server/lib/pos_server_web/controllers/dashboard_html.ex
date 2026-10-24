defmodule TigooServerWeb.DashboardHTML do
  use TigooServerWeb, :html

  import TigooServerWeb.PosLayoutComponents

  embed_templates "dashboard_html/*"

  defp workspace_name(%{company_name: company_name}, _user)
       when is_binary(company_name) and company_name != "",
       do: company_name

  defp workspace_name(%{name: name}, _user) when is_binary(name) and name != "",
    do: name

  defp workspace_name(_company, %{tenant: tenant}) when is_binary(tenant) and tenant != "",
    do: tenant

  defp workspace_name(_company, _user), do: "Workspace"

  defp company_field(company, field, fallback \\ nil)

  defp company_field(company, field, fallback) when is_map(company) do
    Map.get(company, field) || Map.get(company, Atom.to_string(field)) || fallback
  end

  defp company_field(_company, _field, fallback), do: fallback
end
