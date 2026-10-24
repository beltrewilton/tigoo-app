defmodule TigooServerWeb.DashboardComponents do
  use TigooServerWeb, :html

  attr :active, :any, required: true
  attr :tenant, :string, default: nil

  def dashboard_sidebar(assigns) do
    assigns = assign(assigns, :addons, TigooServer.Addons.enabled_for(assigns.tenant))

    ~H"""
    <aside class="dashboard-sidebar" aria-label="Primary navigation" data-i18n-aria-label="layout.nav.primary">
      <div class="dashboard-sidebar-brand">
        <a class="brand" href={~p"/pos/dashboard"} aria-label="tigoo dashboard">
          <img src={~p"/images/icon-app.png"} alt="tigoo" />
        </a>
        <button
          class="btn"
          data-variant="ghost"
          data-size="icon-sm"
          type="button"
          data-dashboard-sidebar-toggle
          aria-label="Collapse navigation"
          data-i18n-aria-label="layout.nav.collapse"
          aria-expanded="true"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path d="M9 18l6-6-6-6" />
          </svg>
        </button>
      </div>
      <nav class="dashboard-nav" aria-label="Dashboard navigation" data-i18n-aria-label="dashboard.dashboard">
        <a
          class={[@active == :dash && "is-active"]}
          href={~p"/pos/dashboard"}
          aria-current={if @active == :dash, do: "page"}
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <rect x="3" y="3" width="7" height="7" rx="1" /><rect
              x="14"
              y="3"
              width="7"
              height="7"
              rx="1"
            /><rect x="3" y="14" width="7" height="7" rx="1" /><rect
              x="14"
              y="14"
              width="7"
              height="7"
              rx="1"
            />
          </svg><span class="dashboard-sidebar-label" data-i18n="dashboard.dashboard">Dashboard</span>
        </a>
        <a
          class={[@active == :addons && "is-active"]}
          href={~p"/pos/addons/install"}
          aria-current={if @active == :addons, do: "page"}
        >
          <span aria-hidden="true">＋</span><span class="dashboard-sidebar-label" data-i18n="dashboard.installAddon">Install Addon</span>
        </a>
        <a
          :for={addon <- @addons}
          class={[@active == addon.identifier && "is-active"]}
          href={"/pos/addons/#{addon.identifier}"}
          aria-current={if @active == addon.identifier, do: "page"}
        >
          <span aria-hidden="true">{addon.icon}</span><span class="dashboard-sidebar-label"><%= addon.name %></span>
        </a>
      </nav>
      <div class="dashboard-sidebar-footer">
        <span class="dashboard-sidebar-label" data-i18n="dashboard.workspaceManagement">Workspace management</span>
      </div>
    </aside>
    """
  end
end
