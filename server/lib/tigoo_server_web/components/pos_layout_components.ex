defmodule TigooServerWeb.PosLayoutComponents do
  @moduledoc false
  use TigooServerWeb, :html

  alias TigooServer.Accounts.Scope

  attr(:id, :string, required: true)
  attr(:class, :string, default: "pos-shell")
  attr(:active_page, :atom, required: true)
  attr(:scope, :map, required: true)
  attr(:stores, :list, required: true)
  attr(:store_id, :any, required: true)
  attr(:print_relay_token, :string, default: nil)
  attr(:rest, :global)

  slot(:before_layout)
  slot(:inner_block, required: true)

  def pos_layout(assigns) do
    ~H"""
    <main
      id={@id}
      class={@class}
      data-store-id={@store_id}
      data-print-relay-token={@print_relay_token}
      data-tenant={@scope.tenant}
      data-print-logo={print_logo(@stores, @store_id)}
      data-print-logo-version={print_logo_version(@stores, @store_id)}
      {@rest}
    >
      <span
        id={"#{@id}-store-preference"}
        phx-hook="StorePreference"
        data-store-id={@store_id}
        hidden
      >
      </span>
      <span
        id={"#{@id}-print-relay"}
        phx-hook="PrintRelay"
        phx-update="ignore"
        data-store-id={@store_id}
        data-print-relay-token={@print_relay_token}
        data-tenant={@scope.tenant}
        data-print-logo={print_logo(@stores, @store_id)}
        data-print-logo-version={print_logo_version(@stores, @store_id)}
        hidden
      >
      </span>
      <span
        id={"#{@id}-printer-session"}
        phx-hook="PrinterSession"
        phx-update="ignore"
        hidden
      >
      </span>
      {render_slot(@before_layout)}
      <details class="mobile-nav-menu">
        <summary class="mobile-nav-trigger" aria-label="Open navigation">
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.4"
            stroke-linecap="round"
          >
            <path d="M4 7h16M4 12h16M4 17h16" />
          </svg>
        </summary>
        <div
          class="mobile-nav-panel"
          role="navigation"
          aria-label="Primary navigation"
          data-i18n-aria-label="layout.nav.primary"
        >
          <a
            :if={nav_allowed?(@scope, :dashboard)}
            class="mobile-nav-link"
            href={nav_href(:dashboard, @active_page, @store_id)}
            aria-current={current_page(@active_page, :dashboard)}
          >
            Dashboard
          </a>
          <a
            :if={nav_allowed?(@scope, :pos)}
            class="mobile-nav-link"
            href={nav_href(:pos, @active_page, @store_id)}
            aria-current={current_page(@active_page, :pos)}
          >
            POS
          </a>
          <a :if={nav_allowed?(@scope, :ecf_tests)} class="mobile-nav-link"
            href={nav_href(:ecf_tests, @active_page, @store_id)}
            aria-current={current_page(@active_page, :ecf_tests)}>eCF Test history</a>
          <a
            :if={nav_allowed?(@scope, :invoices)}
            class="mobile-nav-link"
            href={nav_href(:invoices, @active_page, @store_id)}
            aria-current={current_page(@active_page, :invoices)}
          >
            Invoice report
          </a>
          <a
            :if={nav_allowed?(@scope, :reconciliation)}
            class="mobile-nav-link"
            href={nav_href(:reconciliation, @active_page, @store_id)}
            aria-current={current_page(@active_page, :reconciliation)}
          >
            Cash reconciliation
          </a>
          <a
            :if={nav_allowed?(@scope, :customers)}
            class="mobile-nav-link"
            href={nav_href(:customers, @active_page, @store_id)}
            aria-current={current_page(@active_page, :customers)}
          >
            Customers
          </a>
          <a
            :if={nav_allowed?(@scope, :inventory)}
            class="mobile-nav-link"
            href={nav_href(:inventory, @active_page, @store_id)}
            aria-current={current_page(@active_page, :inventory)}
          >
            Inventory
          </a>
          <a
            :if={nav_allowed?(@scope, :orders)}
            class="mobile-nav-link"
            href={nav_href(:orders, @active_page, @store_id)}
            aria-current={current_page(@active_page, :orders)}
          >
            Purchase orders
          </a>
          <a
            :if={nav_allowed?(@scope, :installed_addons)}
            class="mobile-nav-link"
            href={nav_href(:installed_addons, @active_page, @store_id)}
            aria-current={current_page(@active_page, :installed_addons)}
          >
            Installed Add-ons
          </a>
          <a
            :if={nav_allowed?(@scope, :company_settings)}
            class="mobile-nav-link"
            href={nav_href(:company_settings, @active_page, @store_id)}
            aria-current={current_page(@active_page, :company_settings)}
          >
            Company settings
          </a>
          <a
            :if={nav_allowed?(@scope, :sequences)}
            class="mobile-nav-link"
            href={nav_href(:sequences, @active_page, @store_id)}
            aria-current={current_page(@active_page, :sequences)}
            data-i18n="sequences.title"
          >
            Sequences
          </a>
          <a
            :if={nav_allowed?(@scope, :users)}
            class="mobile-nav-link"
            href={nav_href(:users, @active_page, @store_id)}
            aria-current={current_page(@active_page, :users)}
          >
            Users
          </a>
          <a
            :if={nav_allowed?(@scope, :addons)}
            class="mobile-nav-link"
            href={nav_href(:addons, @active_page, @store_id)}
            aria-current={current_page(@active_page, :addons)}
          >
            Install Addons
          </a>
          <hr class="separator" />
          <details class="mobile-nav-section mobile-store-selector">
            <summary class="mobile-nav-section-trigger">Store</summary>
            <div class="mobile-nav-section-content" role="group" aria-label="Active store">
              <button
                :for={store <- @stores}
                class="mobile-nav-action"
                type="button"
                phx-click="change_store"
                phx-value-store_id={store.id}
                aria-current={selected_store?(store.id, @store_id)}
              >
                <span>{store.name}</span>
                <svg
                  :if={selected_store?(store.id, @store_id)}
                  class="sidebar-menu-check"
                  aria-hidden="true"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2.5"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <path d="M20 6 9 17l-5-5" />
                </svg>
              </button>
            </div>
          </details>
          <details class="mobile-nav-section mobile-theme-selector sidebar-theme-selector">
            <summary class="mobile-nav-section-trigger">Theme</summary>
            <div class="mobile-nav-section-content" role="group" aria-label="Theme">
              <button class="mobile-nav-action" type="button" data-theme="default-light">
                Default Light
              </button>
              <button class="mobile-nav-action" type="button" data-theme="nature-light">
                Nature Light
              </button>
              <button class="mobile-nav-action" type="button" data-theme="nature-dark">
                Nature Dark
              </button>
              <button class="mobile-nav-action" type="button" data-theme="caffeine-light">
                Caffeine Light
              </button>
              <button class="mobile-nav-action" type="button" data-theme="caffeine-dark">
                Caffeine Dark
              </button>
              <button class="mobile-nav-action" type="button" data-theme="bold-tech-light">
                Bold Tech Light
              </button>
              <button class="mobile-nav-action" type="button" data-theme="bold-tech-dark">
                Bold Tech Dark
              </button>
              <button class="mobile-nav-action" type="button" data-theme="doom-64-light">
                Doom 64 Light
              </button>
              <button class="mobile-nav-action" type="button" data-theme="doom-64-dark">
                Doom 64 Dark
              </button>
            </div>
          </details>
          <details class="mobile-nav-section mobile-user-menu">
            <summary class="mobile-user-trigger">
              <span class="avatar avatar-sm" aria-hidden="true">
                <img :if={avatar_image?(@scope)} class="avatar-image" src={@scope.pic} alt="" />
                <span :if={!avatar_image?(@scope)} class="avatar-fallback">
                  {user_initials(@scope)}
                </span>
              </span>
              <span><strong>{user_name(@scope)}</strong><small>{@scope.login}</small></span>
            </summary>
            <div class="mobile-nav-section-content" role="group" aria-label="User menu">
              <.form for={%{}} action={~p"/pos/logout"} method="delete">
                <button class="mobile-nav-action mobile-nav-logout" type="submit">
                  <svg
                    aria-hidden="true"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M10 17l5-5-5-5" /><path d="M15 12H3" /><path d="M21 19V5a2 2 0 0 0-2-2h-6" />
                  </svg>
                  <span data-i18n="layout.user.logout">Logout</span>
                </button>
              </.form>
            </div>
          </details>
        </div>
      </details>
      <nav
        class="sidebar-rail"
        aria-label="Primary navigation"
        data-i18n-aria-label="layout.nav.primary"
      >
        <a
          :if={nav_allowed?(@scope, :dashboard)}
          class="sidebar-link"
          href={nav_href(:dashboard, @active_page, @store_id)}
          aria-current={current_page(@active_page, :dashboard)}
          aria-label="Dashboard"
          data-i18n-aria-label="dashboard.dashboard"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <rect x="3" y="3" width="7" height="9" rx="1" /><rect
              x="14"
              y="3"
              width="7"
              height="5"
              rx="1"
            /><rect x="14" y="12" width="7" height="9" rx="1" /><rect
              x="3"
              y="16"
              width="7"
              height="5"
              rx="1"
            />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :pos)}
          class="sidebar-link"
          href={nav_href(:pos, @active_page, @store_id)}
          aria-current={current_page(@active_page, :pos)}
          aria-label="POS"
          data-i18n-aria-label="layout.nav.pos"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path d="M3 3h18v18H3z" /><path d="M7 7h10v10H7z" />
          </svg>
        </a>
        <a :if={nav_allowed?(@scope, :ecf_tests)} class="sidebar-link"
          href={nav_href(:ecf_tests, @active_page, @store_id)}
          aria-current={current_page(@active_page, :ecf_tests)}
          aria-label="eCF Test history" title="eCF Test history">
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M5 3h14v18H5zM8 7h8M8 11h8M8 15h5" />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :invoices)}
          class="sidebar-link"
          href={nav_href(:invoices, @active_page, @store_id)}
          aria-current={current_page(@active_page, :invoices)}
          aria-label="Invoice report"
          data-i18n-aria-label="layout.nav.invoices"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path d="M4 2v20h16" /><path d="M8 6h8M8 10h8M8 14h5" />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :reconciliation)}
          class="sidebar-link"
          href={nav_href(:reconciliation, @active_page, @store_id)}
          aria-current={current_page(@active_page, :reconciliation)}
          aria-label="Cash reconciliation"
          data-i18n-aria-label="layout.nav.reconciliation"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <rect x="3" y="6" width="18" height="13" rx="2" />
            <path d="M16 6V4H8v2" />
            <path d="M7 11h.01M11 11h6M7 15h.01M11 15h6" />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :customers)}
          class="sidebar-link"
          href={nav_href(:customers, @active_page, @store_id)}
          aria-current={current_page(@active_page, :customers)}
          aria-label="Customers"
          data-i18n-aria-label="layout.nav.customers"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :inventory)}
          class="sidebar-link"
          href={nav_href(:inventory, @active_page, @store_id)}
          aria-current={current_page(@active_page, :inventory)}
          aria-label="Inventory"
          data-i18n-aria-label="layout.nav.inventory"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path d="m12 3 9 5-9 5-9-5 9-5Z" /><path d="m3 12 9 5 9-5M3 16l9 5 9-5" />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :orders)}
          class="sidebar-link"
          href={nav_href(:orders, @active_page, @store_id)}
          aria-current={current_page(@active_page, :orders)}
          aria-label="Purchase orders"
          data-i18n-aria-label="layout.nav.orders"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path d="M6 2h9l3 3v17H6z" /><path d="M9 10h6M9 14h6" />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :installed_addons)}
          class="sidebar-link"
          href={nav_href(:installed_addons, @active_page, @store_id)}
          aria-current={current_page(@active_page, :installed_addons)}
          aria-label="Installed Add-ons"
          data-i18n-aria-label="addons.installedAddons"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
          >
            <path d="M4 4h6v6H4z" /><path d="M14 4h6v6h-6z" /><path d="M4 14h6v6H4z" /><path d="M14 14h6v6h-6z" />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :company_settings)}
          id="company-settings-nav"
          class="sidebar-link"
          href={nav_href(:company_settings, @active_page, @store_id)}
          aria-current={current_page(@active_page, :company_settings)}
          aria-label="Company settings"
          data-i18n-aria-label="layout.nav.companySettings"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <path d="m3 9 2-5h14l2 5" /><path d="M3 9h18v11H3z" /><path d="M7 20v-6h4v6" /><path d="M3 9c0 2 2 3 4 3s4-1 4-3c0 2 2 3 4 3s4-1 4-3" />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :sequences)}
          id="sequences-nav"
          class="sidebar-link"
          href={nav_href(:sequences, @active_page, @store_id)}
          aria-current={current_page(@active_page, :sequences)}
          aria-label="Sequences"
          data-i18n-aria-label="sequences.title"
        >
          <svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor"
            stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M9 5h12M9 12h12M9 19h12M3 4h1v3M3 11h2l-2 3h2M3 18h2v3H3" />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :users)}
          id="users-nav"
          class="sidebar-link"
          href={nav_href(:users, @active_page, @store_id)}
          aria-current={current_page(@active_page, :users)}
          aria-label="Users"
          data-i18n-aria-label="layout.nav.users"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /><path d="M19 8v4M17 10h4" />
          </svg>
        </a>
        <a
          :if={nav_allowed?(@scope, :addons)}
          class="sidebar-link"
          href={nav_href(:addons, @active_page, @store_id)}
          aria-current={current_page(@active_page, :addons)}
          aria-label="Install Addons"
          data-i18n-aria-label="dashboard.installAddon"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <path d="M12 5v14" /><path d="M5 12h14" />
          </svg>
        </a>
        <details
          id={"#{@id}-theme-selector"}
          class="sidebar-menu sidebar-theme-selector"
        >
          <summary
            class="sidebar-menu-trigger"
            aria-label="Choose theme"
            data-i18n-aria-label="layout.theme.choose"
          >
            <svg
              class="sidebar-theme-icon"
              aria-hidden="true"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <circle cx="13.5" cy="6.5" r=".5" fill="currentColor" /><circle
                cx="17.5"
                cy="10.5"
                r=".5"
                fill="currentColor"
              /><circle cx="8.5" cy="7.5" r=".5" fill="currentColor" /><circle
                cx="6.5"
                cy="12.5"
                r=".5"
                fill="currentColor"
              /><path d="M12 3a9 9 0 1 0 0 18 1.5 1.5 0 0 0 1.5-1.5c0-.4-.16-.78-.44-1.06a1.5 1.5 0 0 1 1.06-2.56H16a5 5 0 0 0 0-10Z" />
            </svg>
          </summary>
          <div
            class="user-menu-content sidebar-menu-content"
            role="group"
            aria-label="Theme"
            data-i18n-aria-label="layout.theme.label"
          >
            <button
              :for={{theme, label, i18n_key} <- theme_options()}
              class="sidebar-menu-action"
              type="button"
              data-theme={theme}
            >
              <span data-i18n={i18n_key}>{label}</span>
              <svg
                class="sidebar-menu-check"
                aria-hidden="true"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2.5"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M20 6 9 17l-5-5" />
              </svg>
            </button>
          </div>
        </details>
        <details id={"#{@id}-store-selector"} class="sidebar-menu sidebar-store-selector">
          <summary
            class="sidebar-menu-trigger"
            aria-label="Choose active store"
            data-i18n-aria-label="layout.store.choose"
          >
            <svg
              class="sidebar-store-icon"
              aria-hidden="true"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="m3 9 2-5h14l2 5" /><path d="M3 9h18v11H3z" /><path d="M7 20v-6h4v6" /><path d="M3 9c0 2 2 3 4 3s4-1 4-3c0 2 2 3 4 3s4-1 4-3" />
            </svg>
          </summary>
          <div
            class="user-menu-content sidebar-menu-content"
            role="group"
            aria-label="Active store"
            data-i18n-aria-label="layout.store.active"
          >
            <button
              :for={store <- @stores}
              class="sidebar-menu-action"
              type="button"
              phx-click="change_store"
              phx-value-store_id={store.id}
              aria-current={selected_store?(store.id, @store_id)}
            >
              <span>{store.name}</span>
              <svg
                :if={selected_store?(store.id, @store_id)}
                class="sidebar-menu-check"
                aria-hidden="true"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2.5"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M20 6 9 17l-5-5" />
              </svg>
            </button>
          </div>
        </details>
        <details class="user-menu sidebar-user-menu">
          <summary class="avatar avatar-trigger" aria-label={"Open menu for #{user_name(@scope)}"}>
            <img :if={avatar_image?(@scope)} class="avatar-image" src={@scope.pic} alt="" />
            <span :if={!avatar_image?(@scope)} class="avatar-fallback">{user_initials(@scope)}</span>
          </summary>
          <div
            class="user-menu-content"
            role="group"
            aria-label="User menu"
            data-i18n-aria-label="layout.user.menu"
          >
            <div class="user-menu-identity">
              <span class="avatar avatar-sm" aria-hidden="true">
                <img :if={avatar_image?(@scope)} class="avatar-image" src={@scope.pic} alt="" />
                <span :if={!avatar_image?(@scope)} class="avatar-fallback">
                  {user_initials(@scope)}
                </span>
              </span>
              <span><strong>{user_name(@scope)}</strong><small>{@scope.login}</small></span>
            </div>
            <hr class="separator" />
            <.form for={%{}} action={~p"/pos/logout"} method="delete">
              <button class="user-menu-action" type="submit">
                <svg
                  aria-hidden="true"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <path d="M10 17l5-5-5-5" /><path d="M15 12H3" /><path d="M21 19V5a2 2 0 0 0-2-2h-6" />
                </svg>
                <span data-i18n="layout.user.logout">Logout</span>
              </button>
            </.form>
          </div>
        </details>
      </nav>
      <div class="status-strip" aria-label="System status" data-i18n-aria-label="layout.status.system"
        style={if Map.get(@scope, :ecf_test_enabled, false), do: "background: #b91c1c; color: white;", else: nil}>
        <strong :if={Map.get(@scope, :ecf_test_enabled, false)}>eCF Test</strong>
        <span class="session-store-status" aria-live="polite">{@scope.login}</span>
        <details class="language-switcher">
          <summary aria-label="Change display language" data-i18n-aria-label="layout.status.language">
            <svg
              aria-hidden="true"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <circle cx="12" cy="12" r="9" /><path d="M3 12h18M12 3c2.5 2.5 3.7 5.5 3.7 9S14.5 18.5 12 21c-2.5-2.5-3.7-5.5-3.7-9S9.5 5.5 12 3Z" />
            </svg>
          </summary>
          <div
            class="language-menu"
            role="group"
            aria-label="Change display language"
            data-i18n-aria-label="layout.status.language"
          >
            <button type="button" data-language="en">
              <span><span class="language-flag" aria-hidden="true">🇺🇸</span>English</span>
              <.menu_check />
            </button><button
              type="button"
              data-language="es"
            >
              <span><span class="language-flag" aria-hidden="true">🇩🇴</span>Español</span>
              <.menu_check />
            </button><button type="button" data-language="pt">
              <span><span class="language-flag" aria-hidden="true">🇧🇷</span>Português</span>
              <.menu_check />
            </button>
          </div>
        </details>
        <span
          id={"#{@id}-printer-status"}
          class="printer-status-shell"
          phx-hook="PrinterStatus"
          phx-update="ignore"
        >
          <button
            id={"#{@id}-printer-status-button"}
            class="printer-status"
            style="appearance: none; display: inline-grid; place-items: center; width: 16px; height: 16px; padding: 0; border: 0; background: transparent; line-height: 0; vertical-align: middle;"
            type="button"
            data-printer-status
            data-status="disconnected"
            aria-label="Printer disconnected"
            title="Printer disconnected"
            data-i18n-aria-label="layout.status.printerDisconnected"
            data-i18n-title="layout.status.printerDisconnected"
          >
            <svg
              role="img"
              width="15"
              height="15"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M6 9V3h12v6" /><path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2" /><path d="M6 14h12v7H6z" />
            </svg>
          </button>
        </span>
        <svg
          id={"#{@id}-network-status"}
          class="network-status"
          role="img"
          aria-label="Network connected"
          data-i18n-aria-label="layout.status.networkConnected"
          data-network-status
          data-status="connected"
          phx-hook="NetworkStatus"
          phx-update="ignore"
          title="Network connected"
          data-i18n-title="layout.status.networkConnected"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="3"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path d="M12 20h.01" /><path d="M2 8.82a15 15 0 0 1 20 0" /><path d="M5 12.859a10 10 0 0 1 14 0" /><path d="M8.5 16.429a5 5 0 0 1 7 0" />
        </svg>
      </div>
      {render_slot(@inner_block)}
    </main>
    """
  end

  defp current_page(page, page), do: "page"
  defp current_page(_, _), do: nil

  defp nav_href(active_page, active_page, _store_id), do: "#"
  defp nav_href(:dashboard, _active_page, store_id), do: store_href(~p"/pos/dashboard", store_id)
  defp nav_href(:pos, _active_page, store_id), do: store_href(~p"/pos", store_id)
  defp nav_href(:ecf_tests, _active_page, store_id), do: store_href(~p"/pos/ecf-tests", store_id)
  defp nav_href(:invoices, _active_page, store_id), do: store_href(~p"/pos/invoices", store_id)
  defp nav_href(:reconciliation, _active_page, store_id), do: store_href(~p"/pos/reconciliation", store_id)
  defp nav_href(:customers, _active_page, store_id), do: store_href(~p"/pos/customers", store_id)
  defp nav_href(:inventory, _active_page, store_id), do: store_href(~p"/pos/inventory", store_id)
  defp nav_href(:orders, _active_page, store_id), do: store_href(~p"/pos/orders", store_id)
  defp nav_href(:installed_addons, _active_page, store_id), do: store_href(~p"/pos/addons", store_id)
  defp nav_href(:company_settings, _active_page, store_id), do: store_href(~p"/pos/company-settings", store_id)
  defp nav_href(:sequences, _active_page, store_id), do: store_href(~p"/pos/sequences", store_id)
  defp nav_href(:users, _active_page, store_id), do: store_href(~p"/pos/users", store_id)
  defp nav_href(:addons, _active_page, store_id), do: store_href(~p"/pos/addons/install", store_id)

  defp store_href(path, nil), do: path
  defp store_href(path, ""), do: path
  defp store_href(path, store_id), do: path <> "?" <> URI.encode_query(%{"store_id" => store_id})
  defp nav_allowed?(scope, :ecf_tests), do: Map.get(scope, :ecf_test_enabled, false)
  defp nav_allowed?(scope, page), do: Scope.allowed?(scope, nav_permission(page))

  defp theme_options do
    [
      {"default-light", "Default Light", "layout.theme.defaultLight"},
      {"nature-light", "Nature Light", "layout.theme.natureLight"},
      {"nature-dark", "Nature Dark", "layout.theme.natureDark"},
      {"caffeine-light", "Caffeine Light", "layout.theme.caffeineLight"},
      {"caffeine-dark", "Caffeine Dark", "layout.theme.caffeineDark"},
      {"bold-tech-light", "Bold Tech Light", "layout.theme.boldTechLight"},
      {"bold-tech-dark", "Bold Tech Dark", "layout.theme.boldTechDark"},
      {"doom-64-light", "Doom 64 Light", "layout.theme.doom64Light"},
      {"doom-64-dark", "Doom 64 Dark", "layout.theme.doom64Dark"}
    ]
  end

  defp nav_permission(:dashboard), do: "dashboard.view"
  defp nav_permission(:pos), do: "sales.pos"
  defp nav_permission(:reconciliation), do: "pos.reconciliation"
  defp nav_permission(:customers), do: "pos.customer"
  defp nav_permission(:invoices), do: "sales.view"
  defp nav_permission(:inventory), do: "inventory.view"
  defp nav_permission(:orders), do: "pos.orders"
  defp nav_permission(:installed_addons), do: "pos.addons"
  defp nav_permission(:company_settings), do: "company.settings"
  defp nav_permission(:sequences), do: "company.settings"
  defp nav_permission(:users), do: "user.view"
  defp nav_permission(:addons), do: "pos.addons.install"

  defp selected_store?(store_id, selected_id), do: to_string(store_id) == to_string(selected_id)

  defp menu_check(assigns) do
    ~H"""
    <svg
      class="sidebar-menu-check"
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <path d="M20 6 9 17l-5-5" />
    </svg>
    """
  end

  defp avatar_image?(%{pic: pic}), do: is_binary(pic) and String.trim(pic) != ""
  defp avatar_image?(_), do: false

  defp user_name(%{user: %{name: name}}) when is_binary(name) and name != "", do: name
  defp user_name(%{login: login}) when is_binary(login) and login != "", do: login
  defp user_name(_), do: "User"

  defp user_initials(scope) do
    scope
    |> user_name()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
    |> case do
      "" -> "U"
      initials -> initials
    end
  end

  defp print_logo(stores, store_id) do
    stores
    |> selected_store(store_id)
    |> case do
      %{logo: logo} when is_binary(logo) and logo != "" -> logo
      %{"logo" => logo} when is_binary(logo) and logo != "" -> logo
      _ -> nil
    end
  end

  defp print_logo_version(stores, store_id) do
    case print_logo(stores, store_id) do
      nil -> ""
      logo -> :crypto.hash(:sha256, logo) |> Base.encode16(case: :lower)
    end
  end

  defp selected_store(stores, store_id),
    do: Enum.find(stores || [], &(to_string(Map.get(&1, :id) || Map.get(&1, "id")) == to_string(store_id)))
end
