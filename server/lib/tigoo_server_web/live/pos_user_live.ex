defmodule TigooServerWeb.PosUserLive do
  @moduledoc false
  use TigooServerWeb, :live_view

  import TigooServerWeb.PosLayoutComponents
  import TigooServerWeb.PosUserComponents

  alias TigooServer.{Authentication, TenantContext}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.{InventoryContext, Users}

  @impl true
  def mount(params, session, socket) do
    with token when is_binary(token) <- session["user_token"],
         {:ok, scope} <- Authentication.authenticate(token),
         true <- Scope.allowed?(scope, "user.view"),
         _ <- TenantContext.put_tenant(scope.tenant),
         {:ok, stores} <- InventoryContext.stores(scope),
         %{id: store_id} <- selected_store(stores, Map.get(params, "store_id") || session["store_id"]) do
      socket =
        socket
        |> assign(:page_title, "Tigoo Users")
        |> assign(:scope, scope)
        |> assign(:stores, stores)
        |> assign(:store_id, store_id)
        |> assign(:mode, :list)
        |> assign(:users, [])
        |> assign(:options, %{stores: [], scopes: []})
        |> assign(:filter, "")
        |> assign(:selected_user, nil)
        |> assign(:status, "Loading users...")
        |> assign(:form_status, "")
        |> assign(:saving?, false)
        |> load_users()

      if connected?(socket) and scope.actor == :employee,
        do: Phoenix.PubSub.subscribe(TigooServer.PubSub, "ecf-mode:#{scope.tenant}:#{scope.actor_id}")
      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "User access is required.")
         |> redirect(to: ~p"/pos/login")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.pos_layout
      id="users-live"
      class="pos-shell users-view"
      active_page={:users}
      scope={@scope}
      stores={@stores}
      store_id={@store_id}
      phx-hook="UsersScreen"
    >
      <.unauthorized_users :if={!Scope.allowed?(@scope, "user.view")} />
      <.user_list
        :if={Scope.allowed?(@scope, "user.view") and @mode == :list}
        users={filtered_users(@users, @filter)}
        filter={@filter}
        options={@options}
        scope={@scope}
        status={list_status(@users, @status)}
      />
      <.user_form
        :if={Scope.allowed?(@scope, "user.view") and @mode != :list}
        mode={@mode}
        user={@selected_user}
        options={@options}
        status={@form_status}
        saving={@saving?}
      />
    </.pos_layout>
    """
  end

  @impl true
  def handle_event("change_store", %{"store_id" => id}, socket) do
    with {store_id, ""} <- Integer.parse(id),
         true <- Enum.any?(socket.assigns.stores, &(&1.id == store_id)),
         {:ok, _} <- InventoryContext.authorize_store(socket.assigns.scope, store_id) do
      {:noreply, assign(socket, :store_id, store_id)}
    else
      _ -> {:noreply, put_flash(socket, :error, "The selected store is unavailable.")}
    end
  end

  def handle_event("filter_users", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :filter, String.trim(String.downcase(value)))}

  def handle_event("new_user", _, socket) do
    if Scope.allowed?(socket.assigns.scope, "user.view") do
      {:noreply,
       socket
       |> assign(:mode, :new)
       |> assign(:selected_user, nil)
       |> assign(:form_status, "")
       |> push_event("users:focus-title", %{})}
    else
      {:noreply, assign(socket, :status, "User settings permission is required.")}
    end
  end

  def handle_event("view_user", %{"id" => id}, socket), do: select_user(socket, id, :view)
  def handle_event("edit_user", %{"id" => id}, socket) do
    if Scope.allowed?(socket.assigns.scope, "user.view"),
      do: select_user(socket, id, :edit),
      else: {:noreply, assign(socket, :status, "User settings permission is required.")}
  end

  def handle_event("list_users", _, socket) do
    {:noreply,
     socket
     |> assign(:mode, :list)
     |> assign(:selected_user, nil)
     |> assign(:form_status, "")
     |> push_event("users:focus-title", %{})}
  end

  def handle_event("save_user", %{"user" => attrs} = params, socket) do
    if Scope.allowed?(socket.assigns.scope, "user.view") do
      attrs = normalize_attrs(attrs, params)

      result =
        case params do
          %{"user_id" => id} -> Users.update(socket.assigns.scope, id, attrs)
          _ -> Users.create(socket.assigns.scope, attrs)
        end

      case result do
        {:ok, _user} ->
          {:noreply,
           socket
           |> assign(:saving?, false)
           |> assign(:mode, :list)
           |> assign(:selected_user, nil)
           |> load_users()}

        {:error, reason} ->
          {:noreply, socket |> assign(:saving?, false) |> assign(:form_status, error_message(reason))}
      end
    else
      {:noreply, assign(socket, :form_status, "User settings permission is required.")}
    end
  end

  def handle_event("set_ecf_test", %{"id" => id, "enabled" => enabled}, socket) when enabled in ["true", "false"] do
    case Users.set_ecf_test(socket.assigns.scope, id, enabled == "true") do
      {:ok, _} -> {:noreply, load_users(socket)}
      {:error, reason} -> {:noreply, assign(socket, :status, error_message(reason))}
    end
  end

  def handle_event("deactivate_user", %{"id" => id}, socket) do
    if Scope.allowed?(socket.assigns.scope, "user.view") do
      case Users.deactivate(socket.assigns.scope, id) do
        {:ok, _user} -> {:noreply, load_users(socket)}
        {:error, reason} -> {:noreply, assign(socket, :status, error_message(reason))}
      end
    else
      {:noreply, assign(socket, :status, "User settings permission is required.")}
    end
  end

  @impl true
  def handle_info({:ecf_test_mode, enabled}, socket) do
    {:noreply, socket |> assign(:scope, %{socket.assigns.scope | ecf_test_enabled: enabled}) |> load_users()}
  end

  defp load_users(socket) do
    with {:ok, users} <- Users.list(socket.assigns.scope),
         {:ok, options} <- Users.options(socket.assigns.scope) do
      socket
      |> assign(:users, users)
      |> assign(:options, options)
      |> assign(:status, "")
    else
      {:error, :forbidden} -> assign(socket, :status, "")
      {:error, reason} -> assign(socket, :status, error_message(reason))
    end
  end

  defp select_user(socket, id, mode) do
    case Users.get(socket.assigns.scope, id) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:mode, mode)
         |> assign(:selected_user, user)
         |> assign(:form_status, "")
         |> push_event("users:focus-title", %{})}

      {:error, reason} ->
        {:noreply, assign(socket, :status, error_message(reason))}
    end
  end

  defp normalize_attrs(attrs, params) do
    attrs
    |> Map.put("is_active", if(Map.get(attrs, "is_active") == "1", do: 1, else: 0))
    |> Map.put("store_ids", Enum.map(Map.get(params, "store_ids", []), &to_int/1))
    |> Map.put("scopes", Map.get(params, "scopes", []))
    |> drop_blank_password()
  end

  defp drop_blank_password(%{"password" => ""} = attrs), do: Map.delete(attrs, "password")
  defp drop_blank_password(attrs), do: attrs
  defp to_int(value) when is_integer(value), do: value
  defp to_int(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      {number, _} -> number
      :error -> 0
    end
  end

  defp filtered_users(users, ""), do: users

  defp filtered_users(users, filter) do
    Enum.filter(users, fn user ->
      haystack =
        [user.first_name, user.last_name, user.username, Enum.join(user.scopes || [], " ")]
        |> Enum.filter(&is_binary/1)
        |> Enum.join(" ")
        |> String.downcase()

      String.contains?(haystack, filter)
    end)
  end

  defp list_status([], ""), do: "No users"
  defp list_status(_users, status), do: status

  defp error_message(:forbidden), do: "Forbidden"
  defp error_message(:not_found), do: "User not found."
  defp error_message(%Ecto.Changeset{}), do: "Please review the user details."
  defp error_message(reason), do: to_string(reason)

  defp selected_store(stores, selected_id) do
    selected = Enum.find(stores, &(to_string(&1.id) == to_string(selected_id)))
    selected || List.first(stores)
  end

  defp unauthorized_users(assigns) do
    ~H"""
    <section id="users-screen" class="users-screen application-screen">
      <div class="card unauthorized-card">
        <div class="card-header">
          <p class="eyebrow">Access denied</p>
          <h1 id="users-title" class="card-title">You do not have access to this area.</h1>
          <p class="card-description">Ask an administrator to update your permissions.</p>
        </div>
      </div>
    </section>
    """
  end
end
