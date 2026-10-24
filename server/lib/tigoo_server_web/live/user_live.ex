defmodule TigooServerWeb.UserLive do
  use TigooServerWeb, :live_view

  alias TigooServer.Accounts
  alias TigooServer.Accounts.User

  import TigooServerWeb.DashboardComponents
  import Phoenix.Controller, only: [get_csrf_token: 0]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:users, Accounts.list_users())
     |> assign_user_form(Accounts.change_user(%User{}))
     |> assign_company_form(Accounts.change_company(%TigooServer.Accounts.Company{}))}
  end

  @impl true
  def handle_event("save_user", %{"user" => user_attrs, "company" => company_attrs}, socket) do
    case Accounts.create_company_user(user_attrs, company_attrs) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{user.name} and their company workspace have been created.")
         |> push_navigate(to: ~p"/admin/users")}

      {:error, :user, changeset} ->
        {:noreply, assign_user_form(socket, changeset)}

      {:error, :company, changeset} ->
        {:noreply, assign_company_form(socket, changeset)}

      {:error, :tenant, reason} ->
        IO.inspect(reason, label: "Tenant workspace creation failed")

        {:noreply,
         put_flash(socket, :error, "The tenant workspace could not be created. Please try again.")}
    end
  end

  @impl true
  def handle_event("confirm_user", %{"id" => user_id}, socket) do
    case Accounts.get_user(user_id) do
      %User{} = user ->
        case Accounts.confirm_user(user) do
          {:ok, confirmed_user} ->
            {:noreply,
             socket
             |> assign(:users, Accounts.list_users())
             |> put_flash(:info, "#{confirmed_user.name} has been confirmed.")}

          {:error, _changeset} ->
            {:noreply,
             put_flash(socket, :error, "The user could not be confirmed. Please try again.")}
        end

      nil ->
        {:noreply, put_flash(socket, :error, "The user could not be found.")}
    end
  end

  @impl true
  def render(assigns),
    do: if(assigns.live_action == :new, do: form_page(assigns), else: index_page(assigns))

  defp index_page(assigns) do
    ~H"""
    <main class="dashboard-shell" aria-labelledby="users-title">
      <.dashboard_sidebar active={:admin} />
      <div class="dashboard-main">
        <header class="dashboard-header">
          <div>
            <p class="dashboard-kicker">Administration</p>
            <h1 id="users-title">People</h1>
          </div>
          <div class="dashboard-header-actions">
            <button
              class="btn"
              data-variant="ghost"
              data-size="icon-sm"
              type="button"
              data-theme-toggle
              aria-label="Toggle color theme"
            >
              <span aria-hidden="true">◐</span>
            </button>
            <form action={~p"/admin/logout"} method="post">
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} /><button
                class="btn"
                data-variant="outline"
                data-size="sm"
                type="submit"
              >
                Logout
              </button>
            </form>
            <a class="btn" data-variant="default" data-size="sm" href={~p"/admin/users/new"}>
              Create user
            </a>
          </div>
        </header>
        <div class="dashboard-content">
          <section class="dashboard-intro">
            <h2>Directory</h2>
            <p>Review confirmation status and workspace access.</p>
          </section>
          <section class="dashboard-summary-grid" aria-label="Directory summary">
            <article class="card dashboard-summary-card">
              <div class="card-header">
                <p class="card-description">Total accounts</p>
                <h2 class="card-title">{length(@users)}</h2>
              </div>
              <div class="card-content">
                <p class="dashboard-summary-detail">All user accounts</p>
              </div>
            </article>
            <article class="card dashboard-summary-card">
              <div class="card-header">
                <p class="card-description">Awaiting confirmation</p>
                <h2 class="card-title">{Enum.count(@users, &is_nil(&1.confirmed_at))}</h2>
              </div>
              <div class="card-content">
                <p class="dashboard-summary-detail">Require review</p>
              </div>
            </article>
          </section>
          <section
            class="card dashboard-panel dashboard-table-panel"
            aria-labelledby="directory-title"
          >
            <div class="card-header dashboard-table-header">
              <div>
                <h2 class="card-title" id="directory-title">User directory</h2>
                <p class="card-description">Manage account confirmation and workspaces.</p>
              </div>
              <div class="dashboard-search" role="search">
                <label class="sr-only" for="user-search">Search users</label><svg
                  aria-hidden="true"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                ><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></svg>
                <input
                  class="input"
                  data-size="sm"
                  id="user-search"
                  type="search"
                  placeholder="Search people"
                  data-user-search
                  autocomplete="off"
                />
              </div>
            </div>
            <div class="table-container">
              <table class="table" id="users-table">
                <caption class="sr-only">Retaily user accounts and their confirmation state.</caption>
                <thead>
                  <tr class="table-row">
                    <th class="table-head" scope="col">User</th>
                    <th class="table-head dashboard-workspace-column" scope="col">Workspace</th>
                    <th class="table-head" scope="col">Status</th>
                    <th class="table-head dashboard-action-column" scope="col">
                      <span class="sr-only">Actions</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@users == []} class="table-row">
                    <td class="table-cell users-empty" colspan="4">
                      <strong>No accounts yet.</strong><span>Create a user to start the directory.</span><a
                        class="btn"
                        data-variant="outline"
                        data-size="sm"
                        href={~p"/admin/users/new"}
                      >Create user</a>
                    </td>
                  </tr>
                  <tr
                    :for={user <- @users}
                    class="table-row"
                    data-user-row
                    data-search={String.downcase("#{user.name} #{user.email} #{user.tenant}")}
                  >
                    <td class="table-cell">
                      <div class="user-identity">
                        <span class="user-avatar">{initials(user.name)}</span><span><strong><%= user.name %></strong><small><%= user.email %></small></span>
                      </div>
                    </td>
                    <td class="table-cell dashboard-workspace-column">
                      <span class="workspace-name">{user.tenant || "—"}</span>
                    </td>
                    <td class="table-cell">
                      <span class="status-badge" data-confirmed={not is_nil(user.confirmed_at)}>
                        <i></i>{if user.confirmed_at, do: "Confirmed", else: "Pending"}
                      </span>
                    </td>
                    <td class="table-cell dashboard-action-column">
                      <button
                        :if={is_nil(user.confirmed_at)}
                        class="btn"
                        data-variant="outline"
                        data-size="sm"
                        type="button"
                        phx-click="confirm_user"
                        phx-value-id={user.id}
                      >
                        Confirm
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>
    </main>
    """
  end

  defp form_page(assigns) do
    ~H"""
    <main class="dashboard-shell" aria-labelledby="new-user-title">
      <.dashboard_sidebar active={:admin} />
      <div class="dashboard-main">
        <header class="dashboard-header">
          <div>
            <p class="dashboard-kicker">Administration</p>
            <h1 id="new-user-title">Create user</h1>
          </div>
          <div class="dashboard-header-actions">
            <button
              class="btn"
              data-variant="ghost"
              data-size="icon-sm"
              type="button"
              data-theme-toggle
              aria-label="Toggle color theme"
            >
              <span aria-hidden="true">◐</span>
            </button>
            <form action={~p"/admin/logout"} method="post">
              <input type="hidden" name="_csrf_token" value={get_csrf_token()} /><button
                class="btn"
                data-variant="outline"
                data-size="sm"
                type="submit"
              >
                Logout
              </button>
            </form>
            <a class="btn" data-variant="outline" data-size="sm" href={~p"/admin/users"}>
              Back to users
            </a>
          </div>
        </header>
        <div class="dashboard-content">
          <section class="dashboard-intro">
            <h2>Add a person</h2>
            <p>Create an account and its initial company workspace.</p>
          </section>
          <form class="card dashboard-panel dashboard-user-form" phx-submit="save_user">
            <div class="card-content">
              <fieldset class="form-fieldset">
                <legend>Person</legend>
                <p class="field-description">The account owner for this workspace.</p>
                <div class="form-grid">
                  <.field field={@user_form[:name]} label="Full name" type="text" required /><.field
                    field={@user_form[:email]}
                    label="Email address"
                    type="email"
                    required
                  /><.field
                    field={@user_form[:password]}
                    label="Temporary password"
                    type="password"
                    required
                    minlength={6}
                    description="At least 6 characters."
                  />
                </div>
              </fieldset>
              <fieldset class="form-fieldset">
                <legend>Company workspace</legend>
                <p class="field-description">
                  A workspace groups a company’s stores and permission scopes.
                </p>
                <div class="form-grid">
                  <.field
                    field={@company_form[:company_name]}
                    label="Company name"
                    type="text"
                    required
                  /><.field field={@company_form[:rnc]} label="RNC" type="text" /><.field
                    field={@user_form[:tenant]}
                    label="Workspace ID"
                    type="text"
                    required
                    description="Lowercase letters, numbers, and underscores only."
                  />
                </div>
              </fieldset>
            </div>
            <div class="card-footer form-actions">
              <a class="btn" data-variant="outline" href={~p"/admin/users"}>Cancel</a><button
                class="btn"
                data-variant="default"
                type="submit"
              >Save user</button>
            </div>
          </form>
        </div>
      </div>
    </main>
    """
  end

  attr :field, :any, required: true
  attr :label, :string, required: true
  attr :type, :string, required: true
  attr :required, :boolean, default: false
  attr :minlength, :integer, default: nil
  attr :description, :string, default: nil

  defp field(assigns) do
    ~H"""
    <div class="form-field" data-invalid={@field.errors != [] || nil}>
      <label class="label" for={@field.id}>{@label}</label>
      <input
        class="input"
        id={@field.id}
        name={@field.name}
        type={@type}
        value={if @type == "password", do: nil, else: @field.value}
        required={@required}
        minlength={@minlength}
        autocomplete={if @type == "password", do: "new-password"}
        aria-invalid={if @field.errors == [], do: "false", else: "true"}
      />
      <p :if={@description} class="field-description">{@description}</p>
      <p :for={{message, _} <- @field.errors} class="field-error" role="alert">{message}</p>
    </div>
    """
  end

  defp initials(name),
    do:
      name
      |> String.split(~r/\s+/, trim: true)
      |> Enum.take(2)
      |> Enum.map_join("", &String.first/1)
      |> String.upcase()

  defp assign_user_form(socket, changeset),
    do: assign(socket, :user_form, to_form(changeset, as: :user))

  defp assign_company_form(socket, changeset),
    do: assign(socket, :company_form, to_form(changeset, as: :company))
end
