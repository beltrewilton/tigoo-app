defmodule TigooServerWeb.DashboardController do
  use TigooServerWeb, :controller

  import Ecto.Query, only: [from: 2]

  alias TigooServer.{Accounts, Authentication, Repo}
  alias TigooServer.Accounts.{Company, Scope}
  alias TigooServer.Retaily.{CompanySettings, InventoryContext}

  def index(%{assigns: %{current_scope: scope}} = conn, params) do
    if Scope.allowed?(scope, "dashboard.view"),
      do: render_dashboard(conn, dashboard_user(scope), selected_store_id: params["store_id"]),
      else: redirect(conn, to: landing_path(scope))
  end

  def index(conn, _params), do: redirect(conn, to: ~p"/")

  def create(%{assigns: %{current_scope: %{actor: :admin, actor_id: user_id}}} = conn, params) do
    case Accounts.get_user(user_id) do
      nil ->
        redirect(conn, to: ~p"/")

      user ->
        tenant_attrs = attrs_param(params, "tenant")
        company_attrs = attrs_param(params, "company")

        case Accounts.create_tenant_for_user(user, tenant_attrs, company_attrs) do
          {:ok, updated_user} ->
            {:ok, session_token, _scope} = Authentication.log_in_user(updated_user)

            conn
            |> configure_session(renew: true)
            |> put_session(:user_token, session_token)
            |> put_flash(:info, "Your workspace has been created.")
            |> redirect(external: tenant_dashboard_url(updated_user.tenant))

          {:error, :tenant, changeset} ->
            render_dashboard(conn, user,
              tenant_changeset: changeset,
              company_attrs: company_attrs
            )

          {:error, :company, changeset} ->
            render_dashboard(conn, user, tenant_attrs: tenant_attrs, company_changeset: changeset)

          {:error, :unconfirmed} ->
            conn
            |> put_flash(:error, "Your account must be confirmed before creating a workspace.")
            |> redirect(to: ~p"/pos/dashboard")

          {:error, :tenant_exists} ->
            conn
            |> put_flash(:error, "This account already has a workspace.")
            |> redirect(to: ~p"/pos/dashboard")

          {:error, :provisioning, _reason} ->
            conn
            |> put_flash(:error, "The workspace could not be created. Please try again.")
            |> redirect(to: ~p"/pos/dashboard")
        end
    end
  end

  def create(conn, _params), do: redirect(conn, to: ~p"/")

  def update_logo(%{assigns: %{current_scope: scope}} = conn, %{"company" => params}) do
    if Scope.allowed?(scope, "dashboard.view") do
      case CompanySettings.update_brand_logo(scope, params) do
        {:ok, _company} ->
          conn
          |> put_flash(:info, "Company logo updated.")
          |> redirect(to: ~p"/pos/dashboard")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Company logo could not be updated.")
          |> redirect(to: ~p"/pos/dashboard")
      end
    else
      redirect(conn, to: landing_path(scope))
    end
  end

  def update_logo(conn, _params), do: redirect(conn, to: ~p"/pos/dashboard")

  defp render_dashboard(conn, user, opts) do
    tenant_changeset = tenant_changeset(conn, user, opts)
    company_changeset = company_changeset(conn, opts)

    {stores, store_id} =
      pos_layout_store_assigns(
        conn.assigns.current_scope,
        Keyword.get(opts, :selected_store_id) || get_session(conn, :store_id)
      )

    render(conn, :index,
      user: user,
      company: dashboard_company(conn.assigns.current_scope, user),
      workspace_created?: workspace_created?(conn.assigns.current_scope, user),
      tenant_form: Phoenix.Component.to_form(tenant_changeset, as: :tenant),
      company_form: Phoenix.Component.to_form(company_changeset, as: :company),
      scope: conn.assigns.current_scope,
      stores: stores,
      store_id: store_id
    )
  end

  defp dashboard_user(%{actor: :admin, actor_id: user_id}) do
    Accounts.get_user(user_id) || %{name: "User", tenant: nil, confirmed_at: nil}
  end

  defp dashboard_user(%{user: user, tenant: tenant}) do
    %{
      name: Map.get(user || %{}, :name) || "User",
      tenant: tenant,
      confirmed_at: DateTime.utc_now()
    }
  end

  defp dashboard_company(%{actor: :admin, tenant: tenant}, user) when is_binary(tenant) do
    Accounts.get_company_for_user(user) || first_company(tenant) || fallback_company(tenant)
  rescue
    _ -> fallback_company(tenant)
  end

  defp dashboard_company(%{tenant: tenant}, _user) when is_binary(tenant) do
    Repo.one(from(company in Company, limit: 1), prefix: Triplex.to_prefix(tenant)) ||
      fallback_company(tenant)
  rescue
    _ -> fallback_company(tenant)
  end

  defp dashboard_company(_, _), do: nil

  defp first_company(tenant) do
    Repo.one(from(company in Company, limit: 1), prefix: tenant)
  rescue
    _ -> nil
  end

  defp fallback_company(tenant),
    do: %{company_name: tenant, rnc: nil, brand_logo: nil}

  defp workspace_created?(%{tenant: tenant}, _user) when is_binary(tenant) and tenant != "", do: true
  defp workspace_created?(_scope, %{tenant: tenant}) when is_binary(tenant) and tenant != "", do: true
  defp workspace_created?(_scope, _user), do: false

  defp tenant_changeset(%{assigns: %{current_scope: %{actor: :admin}}}, user, opts) do
    Keyword.get(
      opts,
      :tenant_changeset,
      Accounts.change_tenant(user, Keyword.get(opts, :tenant_attrs, %{}))
    )
  end

  defp tenant_changeset(_conn, _user, _opts), do: Accounts.change_tenant(%Accounts.User{}, %{})

  defp company_changeset(%{assigns: %{current_scope: %{actor: :admin}}}, opts) do
    Keyword.get(
      opts,
      :company_changeset,
      Accounts.change_company(%Company{}, Keyword.get(opts, :company_attrs, %{}))
    )
  end

  defp company_changeset(_conn, _opts), do: Accounts.change_company(%Company{}, %{})

  defp attrs_param(params, key) do
    case Map.get(params, key) do
      attrs when is_map(attrs) -> attrs
      _ -> %{}
    end
  end

  defp tenant_dashboard_url(tenant) do
    url = TigooServerWeb.Endpoint.config(:url)
    host = url |> Keyword.get(:host, "localhost") |> to_string()
    scheme = url |> Keyword.get(:scheme, "https") |> to_string()

    URI.to_string(%URI{scheme: scheme, host: "#{tenant}.#{host}", path: ~p"/pos/dashboard"})
  end

  defp pos_layout_store_assigns(%{tenant: tenant} = scope, selected_id) when is_binary(tenant) do
    with {:ok, stores} <- InventoryContext.stores(scope) do
      store = selected_store(stores, selected_id)
      {stores, store && store.id}
    else
      _ -> {[], nil}
    end
  end

  defp pos_layout_store_assigns(_scope, _selected_id), do: {[], nil}

  defp selected_store(stores, selected_id) do
    Enum.find(stores, &(to_string(&1.id) == to_string(selected_id))) || List.first(stores)
  end

  defp landing_path(scope) do
    cond do
      Scope.admin?(scope) -> ~p"/pos/dashboard"
      Scope.allowed?(scope, "dashboard.view") -> ~p"/pos/dashboard"
      true -> ~p"/pos"
    end
  end
end
