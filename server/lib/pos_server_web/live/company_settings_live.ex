defmodule PosServerWeb.CompanySettingsLive do
  @moduledoc false
  use PosServerWeb, :live_view

  import PosServerWeb.PosLayoutComponents

  alias PosServer.{Authentication, TenantContext}
  alias PosServer.Accounts.Scope
  alias PosServer.Retaily.CompanySettings

  @kinds ~w(price-list store provider)

  @impl true
  def mount(params, session, socket) do
    with token when is_binary(token) <- session["user_token"],
         {:ok, scope} <- Authentication.authenticate(token),
         true <- Scope.allowed?(scope, "company.settings"),
         _ <- TenantContext.put_tenant(scope.tenant),
         {:ok, overview} <- safe_overview(scope) do
      {:ok,
       socket
       |> assign(:page_title, "Tigoo Company settings")
       |> assign(:scope, scope)
       |> assign(:overview, overview)
       |> assign(:stores, overview.stores)
       |> assign(:store_id, selected_store_id(overview.stores, Map.get(params, "store_id") || session["store_id"]))
       |> assign(:editing, nil)
       |> assign(:status, "")}
    else
      {:error, :load_failed} ->
        {:ok,
         socket
         |> put_flash(:error, "Company settings could not be loaded.")
         |> redirect(to: ~p"/pos/dashboard")}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Company settings access is required.")
         |> redirect(to: ~p"/pos")}
    end
  end

  @impl true
  def handle_event("add", %{"kind" => kind}, socket) when kind in @kinds,
    do: {:noreply, assign(socket, :editing, {kind, :new})}

  def handle_event("edit", %{"kind" => kind, "id" => id}, socket) when kind in @kinds do
    with {id, ""} <- Integer.parse(id), true <- entry(socket.assigns.overview, kind, id) do
      {:noreply, assign(socket, :editing, {kind, id})}
    else
      _ -> {:noreply, assign(socket, :status, "This item could not be found.")}
    end
  end

  def handle_event("cancel", _, socket),
    do: {:noreply, socket |> assign(:editing, nil) |> assign(:status, "")}

  def handle_event("change_store", %{"store_id" => id}, socket) do
    with {store_id, ""} <- Integer.parse(id),
         true <- Enum.any?(socket.assigns.stores, &(&1.id == store_id)) do
      {:noreply, assign(socket, :store_id, store_id)}
    else
      _ -> {:noreply, put_flash(socket, :error, "The selected store is unavailable.")}
    end
  end

  def handle_event("save", %{"kind" => kind} = params, socket) when kind in @kinds do
    result =
      case {kind, socket.assigns.editing} do
        {"price-list", {"price-list", :new}} ->
          safe_company_settings(fn ->
            CompanySettings.create_price_list(socket.assigns.scope, %{
              "label" => Map.get(params, "name", "")
            })
          end)

        {"price-list", {"price-list", id}} ->
          safe_company_settings(fn ->
            CompanySettings.update_price_list(socket.assigns.scope, id, %{
              "label" => Map.get(params, "name", "")
            })
          end)

        {"store", {"store", :new}} ->
          safe_company_settings(fn ->
            CompanySettings.create_store(socket.assigns.scope, store_attrs(params))
          end)

        {"store", {"store", id}} ->
          safe_company_settings(fn ->
            CompanySettings.update_store(socket.assigns.scope, id, store_attrs(params))
          end)

        {"provider", {"provider", :new}} ->
          safe_company_settings(fn ->
            CompanySettings.create_provider(socket.assigns.scope, %{
              "name" => Map.get(params, "name", "")
            })
          end)

        {"provider", {"provider", id}} ->
          safe_company_settings(fn ->
            CompanySettings.update_provider(socket.assigns.scope, id, %{
              "name" => Map.get(params, "name", "")
            })
          end)

        _ ->
          {:error, :invalid_edit}
      end

    case result do
      {:ok, _} -> {:noreply, socket |> assign(:editing, nil) |> assign(:status, "") |> reload()}
      {:error, reason} -> {:noreply, assign(socket, :status, error_message(reason, kind, :save))}
    end
  end

  def handle_event("delete", %{"kind" => kind, "id" => id}, socket)
      when kind in ["price-list", "provider"] do
    with {id, ""} <- Integer.parse(id) do
      result =
        case kind do
          "price-list" -> safe_company_settings(fn -> CompanySettings.delete_price_list(id) end)
          "provider" -> safe_company_settings(fn -> CompanySettings.delete_provider(id) end)
        end

      case result do
        {:ok, _} ->
          {:noreply, socket |> assign(:editing, nil) |> assign(:status, "") |> reload()}

        {:error, reason} ->
          {:noreply, assign(socket, :status, error_message(reason, kind, :delete))}
      end
    else
      _ -> {:noreply, assign(socket, :status, "This item could not be found.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.pos_layout
      id="company-settings-live"
      class="pos-shell invoice-view"
      active_page={:company_settings}
      scope={@scope}
      stores={@stores}
      store_id={@store_id}
      phx-hook="CompanySettings"
      data-editing={editing_key(@editing)}
    >
      <section
        class="catalog-panel"
        data-view="company-settings"
        aria-labelledby="company-settings-title"
      >
        <section
          id="company-settings-screen"
          class="company-settings-screen"
          aria-labelledby="company-settings-title"
        >
          <div class="company-settings-fixed">
            <header class="topbar company-settings-topbar">
              <div class="brand-lockup">
                <span class="brand-mark" aria-hidden="true">E</span>
                <div>
                  <p class="eyebrow" data-i18n="company.company">Company</p>
                  <h2 id="company-settings-title" tabindex="-1" data-i18n="company.title">Company settings</h2>
                </div>
              </div>
              <a class="btn" data-variant="outline" href={~p"/pos/sequences?store_id=#{@store_id}"}>
                <span data-i18n="sequences.title">Sequences</span>
              </a>
            </header>
            <article class="card company-summary" aria-labelledby="company-summary-title">
              <div class="card-header">
                <h3 id="company-summary-title" class="card-title" data-i18n="company.currentCompany">Current company</h3>
                <p id="company-settings-company" class="card-description">
                  {company_name(@overview.company)}
                </p>
              </div>
            </article>
            <p id="company-settings-status" class="company-settings-status" role="status">
              {@status}
            </p>
          </div>
          <div class="company-settings-cards">
            <.settings_card
              kind="price-list"
              title="Price lists"
              description="Manage the labels used for product prices."
              add_label="Add price list"
              entries={@overview.price_lists}
              editing={@editing}
              empty="No price lists yet."
              company={@overview.company}
            />
            <.settings_card
              kind="store"
              title="Stores"
              description="Manage your company’s store locations."
              add_label="Add store"
              entries={@overview.stores}
              editing={@editing}
              empty="No stores yet."
              company={@overview.company}
            />
            <.settings_card
              kind="provider"
              title="Providers"
              description="Manage the providers used for purchase orders."
              add_label="Add provider"
              entries={@overview.providers}
              editing={@editing}
              empty="No providers yet."
              company={@overview.company}
            />
          </div>
        </section>
      </section>
    </.pos_layout>
    """
  end

  attr :kind, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, required: true
  attr :add_label, :string, required: true
  attr :entries, :list, required: true
  attr :editing, :any, required: true
  attr :empty, :string, required: true
  attr :company, :any, required: true

  defp settings_card(assigns) do
    ~H"""
    <article class="card company-settings-card" aria-labelledby={title_id(@kind)}>
      <div class="card-header company-settings-card-header">
        <div>
          <h3 id={title_id(@kind)} class="card-title" data-i18n={card_title_key(@kind)}>{@title}</h3>
          <p class="card-description" data-i18n={card_description_key(@kind)}>{@description}</p>
        </div>
        <button
          id={add_id(@kind)}
          class="btn"
          type="button"
          data-variant="default"
          data-size="sm"
          phx-click="add"
          phx-value-kind={@kind}
        >
          <span data-i18n={card_add_key(@kind)}>{@add_label}</span>
        </button>
      </div>
      <div id={content_id(@kind)} class="card-content">
        <.setting_form :if={@editing == {@kind, :new}} kind={@kind} entry={nil} company={@company} />
        <%= for entry <- @entries do %>
          <.setting_form
            :if={@editing == {@kind, entry.id}}
            kind={@kind}
            entry={entry}
            company={@company}
          />
          <.setting_row :if={@editing != {@kind, entry.id}} kind={@kind} entry={entry} />
        <% end %>
        <p
          :if={@entries == [] and @editing != {@kind, :new}}
          class="field-description company-settings-empty"
        >
          <span data-i18n={card_empty_key(@kind)}>{@empty}</span>
        </p>
      </div>
    </article>
    """
  end

  attr :kind, :string, required: true
  attr :entry, :any, required: true
  attr :company, :any, required: true

  defp setting_form(assigns) do
    ~H"""
    <form class="form company-setting-form" phx-submit="save" phx-value-kind={@kind}>
      <input type="hidden" name="kind" value={@kind} />
        <.field
          label={setting_name_label(@kind)}
          label_key={setting_name_label_key(@kind)}
          name="name"
          value={value(@entry, setting_name_key(@kind))}
          required
        />
        <%= if @kind == "store" do %>
          <p class="field-description store-company-context">
            <span data-i18n="company.company">Company</span>: {value(@company, :name) || "Current company"}
          </p>
          <.field label="Slogan" label_key="company.slogan" name="slogan" value={value(@entry, :slogan)} /><.field
            label="Address"
            label_key="company.address"
            name="address"
            value={value(@entry, :address)}
            multiline
          />
          <div
            id={"store-logo-field-#{value(@entry, :id) || "new"}"}
            class="form-field store-logo-field"
            phx-update="ignore"
          >
            <div class="product-image-dropzone store-logo-dropzone" tabindex="0" role="button">
              <img
                class="product-image-preview store-logo-preview"
                src={value(@entry, :logo)}
                alt="Store logo preview"
                data-i18n-alt="company.storeLogoPreview"
                hidden={is_nil(value(@entry, :logo))}
              /><label class="label" data-i18n="company.storeLogo">Store logo</label>
              <p class="field-description" data-i18n="company.uploadHelp">
                Drop an image here or choose a file (max 10 MB). It will be resized and stored as Base64.
              </p>
              <input class="input" type="file" accept="image/*" />
            </div>
            <input class="store-logo-value" type="hidden" name="logo" value={value(@entry, :logo)} /><button
              :if={value(@entry, :logo)}
              class="btn store-logo-remove"
              type="button"
              data-variant="outline"
              data-remove-store-logo
            >
              <span data-i18n="company.removeLogo">Remove logo</span>
            </button>
          </div>
        <% end %>
      <div class="form-actions">
        <button class="btn" type="button" data-variant="outline" phx-click="cancel"><span data-i18n="common.cancel">Cancel</span></button><button
          class="btn"
          type="submit"
          data-variant="default"
        ><span data-i18n={submit_label_key(@entry)}>{submit_label(@kind, @entry)}</span></button>
      </div>
    </form>
    """
  end

  attr :label, :string, required: true
  attr :label_key, :string, required: true
  attr :name, :string, required: true
  attr :value, :any, default: nil
  attr :type, :string, default: "text"
  attr :required, :boolean, default: false
  attr :multiline, :boolean, default: false

  defp field(assigns) do
    ~H"""
    <div class="form-field">
      <label class="label" for={"company-setting-#{@name}"} data-i18n={@label_key}>{@label}</label><textarea
        :if={@multiline}
        id={"company-setting-#{@name}"}
        class="input"
        name={@name}
      >{@value}</textarea><input
        :if={!@multiline}
        id={"company-setting-#{@name}"}
        class="input"
        name={@name}
        type={@type}
        inputmode={if @type == "number", do: "numeric"}
        value={@value}
        required={@required}
      />
    </div>
    """
  end

  attr :kind, :string, required: true
  attr :entry, :map, required: true

  defp setting_row(assigns) do
    ~H"""
    <div class="company-setting-row">
      <div>
        <img
          :if={@kind == "store" and value(@entry, :logo)}
          class="store-logo-thumbnail"
          src={value(@entry, :logo)}
          alt=""
        /><strong>{row_title(@kind, @entry)}</strong>
        <p class="field-description">{row_description(@kind, @entry)}</p>
      </div>
      <div class="company-setting-actions">
        <button
          class="btn"
          type="button"
          data-variant="outline"
          data-size="sm"
          phx-click="edit"
          phx-value-kind={@kind}
          phx-value-id={@entry.id}
        >
          <span data-i18n="common.edit">Edit</span>
        </button><button
          :if={@kind != "store"}
          class="btn"
          type="button"
          data-variant="destructive"
          data-size="sm"
          data-company-settings-confirm={delete_message(@kind)}
          data-delete-kind={@kind}
          data-delete-id={@entry.id}
        ><span data-i18n="common.delete">Delete</span></button>
      </div>
    </div>
    """
  end

  defp reload(socket) do
    case safe_overview(socket.assigns.scope) do
      {:ok, overview} ->
        stores = overview.stores
        store_id = selected_store_id(stores, socket.assigns.store_id)
        assign(socket, overview: overview, stores: stores, store_id: store_id)

      _ ->
        assign(socket, :status, "Company settings could not be loaded.")
    end
  end

  defp store_attrs(params), do: Map.take(params, ["name", "slogan", "address", "logo"])

  defp selected_store_id(stores, selected_id) do
    case Integer.parse(to_string(selected_id || "")) do
      {id, ""} ->
        if(Enum.any?(stores, &(&1.id == id)),
          do: id,
          else: stores |> List.first() |> then(&(&1 && &1.id))
        )

      _ ->
        stores |> List.first() |> then(&(&1 && &1.id))
    end
  end

  defp entry(overview, "price-list", id), do: Enum.find(overview.price_lists, &(&1.id == id))
  defp entry(overview, "store", id), do: Enum.find(overview.stores, &(&1.id == id))
  defp entry(overview, "provider", id), do: Enum.find(overview.providers, &(&1.id == id))
  defp value(nil, _key), do: nil
  defp value(entry, key), do: Map.get(entry, key) || Map.get(entry, Atom.to_string(key))

  defp company_name(company),
    do:
      [
        value(company, :company_name) || value(company, :name),
        if(value(company, :rnc), do: "RNC #{value(company, :rnc)}")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

  defp safe_overview(scope) do
    CompanySettings.overview(scope)
  rescue
    _ -> {:error, :load_failed}
  end

  defp safe_company_settings(fun) when is_function(fun, 0) do
    fun.()
  rescue
    _ -> {:error, :load_failed}
  end

  defp editing_key(nil), do: ""
  defp editing_key({kind, id}), do: "#{kind}:#{id}"
  defp title_id("price-list"), do: "price-lists-title"
  defp title_id("store"), do: "stores-title"
  defp title_id("provider"), do: "providers-title"
  defp add_id("price-list"), do: "add-price-list"
  defp add_id("store"), do: "add-store"
  defp add_id("provider"), do: "add-provider"
  defp content_id("price-list"), do: "price-lists-content"
  defp content_id("store"), do: "stores-content"
  defp content_id("provider"), do: "providers-content"
  defp card_title_key("price-list"), do: "company.priceLists"
  defp card_title_key("store"), do: "company.stores"
  defp card_title_key("provider"), do: "company.providers"
  defp card_description_key("price-list"), do: "company.priceListsCopy"
  defp card_description_key("store"), do: "company.storesCopy"
  defp card_description_key("provider"), do: "company.providersCopy"
  defp card_add_key("price-list"), do: "company.addPriceList"
  defp card_add_key("store"), do: "company.addStore"
  defp card_add_key("provider"), do: "company.addProvider"
  defp card_empty_key("price-list"), do: "company.noPriceLists"
  defp card_empty_key("store"), do: "company.noStores"
  defp card_empty_key("provider"), do: "company.noProviders"
  defp setting_name_label("price-list"), do: "Price list label"
  defp setting_name_label("provider"), do: "Provider name"
  defp setting_name_label(_), do: "Store name"
  defp setting_name_label_key("price-list"), do: "company.priceListLabel"
  defp setting_name_label_key("provider"), do: "company.providerName"
  defp setting_name_label_key(_), do: "company.storeName"
  defp setting_name_key("price-list"), do: :label
  defp setting_name_key(_), do: :name
  defp submit_label_key(entry) when not is_nil(entry), do: "common.save"
  defp submit_label_key(nil), do: "common.create"
  defp submit_label(_kind, entry) when not is_nil(entry), do: "Save"
  defp submit_label(_, nil), do: "Create"
  defp row_title("price-list", entry), do: value(entry, :label)
  defp row_title(_, entry), do: value(entry, :name)

  defp row_description("store", entry) do
    case [value(entry, :slogan), value(entry, :address)]
         |> Enum.reject(&(&1 in [nil, ""]))
         |> Enum.join(" · ") do
      "" -> "No store details provided"
      text -> text
    end
  end

  defp row_description("price-list", entry), do: value(entry, :price_key) || ""
  defp row_description(_, _), do: ""
  defp delete_message("price-list"), do: "Delete this price list?"
  defp delete_message(kind), do: "Delete this #{kind}?"
  defp error_message(_reason, "price-list", :save), do: "Could not save price list."
  defp error_message(_reason, "store", :save), do: "Could not save store."
  defp error_message(_reason, "provider", :save), do: "Could not save provider."
  defp error_message(_reason, "price-list", :delete), do: "Could not delete price list."
  defp error_message(_reason, "provider", :delete), do: "Could not delete provider."
end
