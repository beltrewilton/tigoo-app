defmodule TigooServerWeb.CustomerComponents do
  @moduledoc false
  use TigooServerWeb, :html

  attr :customers, :list, required: true
  attr :search, :string, required: true
  attr :status, :string, required: true
  attr :loading, :boolean, default: false
  attr :store_id, :any, default: nil

  def customer_list(assigns) do
    ~H"""
    <section id="customers-screen" class="customers-screen" aria-labelledby="customers-title">
      <div class="invoice-report-fixed">
        <header class="topbar invoice-topbar">
          <div class="brand-lockup">
            <span class="brand-mark" aria-hidden="true">E</span>
            <div>
              <p class="eyebrow" data-i18n="pos.customers.customers">Customers</p>
              <h2 id="customers-title" tabindex="-1" data-i18n="pos.customers.customerList">
                Customer list
              </h2>
            </div>
          </div>
          <div class="customers-header-actions">
            <button
              id="create-customer"
              class="btn"
              type="button"
              data-variant="default"
              phx-click="open_customer_dialog"
              aria-haspopup="dialog"
            >
              <span data-i18n="pos.customers.createCustomer">Create customer</span>
            </button>
            <a id="customers-back" class="btn" data-variant="outline" href={store_path("/pos", @store_id)}>
              <span data-i18n="common.back">Back</span>
            </a>
          </div>
        </header>
      </div>
      <div class="customer-search-field search-field">
        <label class="sr-only" for="customer-search" data-i18n="pos.customers.searchCustomers">
          Search customers
        </label>
        <svg class="search-icon" aria-hidden="true"><use href="#ui-icon-search" /></svg>
        <input
          id="customer-search"
          class="input"
          type="search"
          name="value"
          value={@search}
          phx-keyup="search_customers"
          phx-change="search_customers"
          phx-debounce="220"
          autocomplete="off"
          placeholder="Search customers by name or phone"
          data-i18n-placeholder="pos.customers.searchCustomersPlaceholder"
        />
        <button
          :if={@search != ""}
          class="btn search-clear"
          type="button"
          phx-click={JS.push("search_customers", value: %{value: ""})}
        >
          ×
        </button>
      </div>
      <p id="customers-status" class="customers-status" role="status">{@status}</p>
      <div class="table-container customer-table-container">
        <table class="table customer-table">
          <caption class="table-caption" data-i18n="pos.customers.accountsCaption">
            Customer accounts and purchase activity.
          </caption>
          <thead>
            <tr class="table-row">
              <th class="table-head" scope="col" data-i18n="common.name">Name</th>
              <th class="table-head" scope="col" data-i18n="common.documentId">Document ID</th>
              <th class="table-head" scope="col" data-i18n="common.phone">Phone</th>
              <th
                class="table-head"
                scope="col"
                data-customer-management-column
                data-i18n="common.email"
              >
                Email
              </th>
              <th
                class="table-head"
                scope="col"
                data-customer-management-column
                data-i18n="pos.customers.wholesale"
              >
                Wholesale
              </th>
              <th
                class="table-head"
                scope="col"
                data-customer-management-column
                data-i18n="pos.customers.pendingBalance"
              >
                Pending balance
              </th>
              <th
                class="table-head"
                scope="col"
                data-customer-management-column
                data-i18n="pos.customers.lastPurchase"
              >
                Last purchase
              </th>
              <th class="table-head" scope="col">
                <span id="customers-action-heading" class="sr-only" data-i18n="common.view">
                  View
                </span>
              </th>
            </tr>
          </thead>
          <tbody id="customers-table-body">
            <.customer_row :for={customer <- @customers} customer={customer} />
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr :customer, :map, required: true

  def customer_row(assigns) do
    ~H"""
    <tr class="table-row">
      <td class="table-cell" data-label="Name" data-i18n-data-label="common.name">
        {dash(@customer.name)}
      </td>
      <td class="table-cell" data-label="Document ID" data-i18n-data-label="common.documentId">
        {dash(@customer.document_id)}
      </td>
      <td class="table-cell" data-label="Phone" data-i18n-data-label="common.phone">
        {dash(@customer.celphone)}
      </td>
      <td class="table-cell" data-label="Email" data-i18n-data-label="common.email">
        {dash(@customer.email)}
      </td>
      <td class="table-cell" data-label="Wholesale" data-i18n-data-label="pos.customers.wholesale">
        <span data-i18n={if wholesale?(@customer), do: "common.yes", else: "common.no"}>
          {if wholesale?(@customer), do: "Yes", else: "No"}
        </span>
      </td>
      <td
        class="table-cell numeric"
        data-label="Pending balance"
        data-i18n-data-label="pos.customers.pendingBalance"
      >
        {money(max(float(@customer.pending_balance), 0.0))}
      </td>
      <td
        class="table-cell"
        data-label="Last purchase"
        data-i18n-data-label="pos.customers.lastPurchase"
      >
        {date_only(@customer.last_purchase_date)}
      </td>
      <td class="table-cell customer-action">
        <button
          class="btn"
          type="button"
          data-variant="outline"
          data-size="sm"
          phx-click="open_customer_detail"
          phx-value-id={@customer.id}
          aria-label={"View: #{dash(@customer.name)}"}
        >
          <span data-i18n="common.view">View</span>
        </button>
      </td>
    </tr>
    """
  end

  attr :detail, :map, default: nil
  attr :loading, :boolean, default: false
  attr :store_id, :any, default: nil

  def customer_detail(assigns) do
    ~H"""
    <section
      id="customer-detail-screen"
      class="invoice-report customer-detail-screen"
      aria-labelledby="customer-detail-title"
    >
      <div class="invoice-report-fixed">
        <header class="topbar invoice-topbar">
          <div class="brand-lockup">
            <span class="brand-mark" aria-hidden="true">E</span>
            <div>
              <p class="eyebrow" data-i18n="pos.customers.customers">Customers</p>
              <h2 id="customer-detail-title" tabindex="-1" data-i18n="pos.customers.detail">
                Customer detail
              </h2>
            </div>
          </div>
          <button
            id="customer-detail-back"
            class="btn"
            type="button"
            data-variant="outline"
            data-size="sm"
            phx-click="close_customer_detail"
          >
            <span data-i18n="pos.customers.backToCustomers">Back to customers</span>
          </button>
        </header>
      </div>
      <article id="customer-detail" class="card customer-detail-card" aria-live="polite">
        <.customer_detail_content :if={!@loading and @detail} detail={@detail} store_id={@store_id} />
      </article>
    </section>
    """
  end

  attr :detail, :map, required: true
  attr :store_id, :any, default: nil

  def customer_detail_content(assigns) do
    ~H"""
    <% customer = @detail.customer %>
    <% summary = @detail.summary %>
    <div class="card-header">
      <div>
        <p class="eyebrow" data-i18n="pos.customers.account">Customer account</p>
        <h3 class="card-title">{dash(customer.name, "Customer")}</h3>
        <p class="card-description">
          {dash(customer.document_id, "No document ID")} · {dash(customer.celphone, "No phone")}
        </p>
      </div>
      <button
        class="btn"
        type="button"
        data-variant="outline"
        data-size="sm"
        phx-click="open_customer_edit"
        phx-value-id={customer.id}
        aria-haspopup="dialog"
      >
        <span data-i18n="common.edit">Edit</span>
      </button>
    </div>
    <div class="card-content">
      <p class="card-description">
        {dash(customer.address, "No address")} · {dash(customer.email, "No email")} ·
        <span data-i18n={
          if wholesale?(customer), do: "pos.customers.wholesale", else: "pos.customers.retail"
        }>
          {if wholesale?(customer), do: "Wholesale", else: "Retail"}
        </span>
        · <span data-i18n="pos.customers.created">Created</span> {customer_date(customer.date_create)}
      </p>
      <section class="invoice-summary">
        <.summary_card
          title="Pending balance"
          value={money(float(value(summary, :pending_balance)))}
          numeric
        />
        <.summary_card
          title="Total invoiced"
          value={money(float(value(summary, :total_invoiced)))}
          numeric
        />
        <.summary_card title="Total paid" value={money(float(value(summary, :total_paid)))} numeric />
        <.summary_card
          title="Outstanding balance"
          value={money(float(value(summary, :pending_balance)))}
          numeric
        />
        <.summary_card title="Purchases" value={value(summary, :purchase_count) || 0} numeric />
        <article class="card">
          <div class="card-header">
            <p class="card-title">Last purchase</p>
          </div>
          <div class="card-content">
            <p class="card-description">{customer_date(value(summary, :last_purchase_date))}</p>
          </div>
        </article>
      </section>
      <div class="table-container">
        <p class="invoice-table-section-title" data-i18n="pos.customers.purchaseHistory">
          Purchase history
        </p>
        <table class="table">
          <thead>
            <tr class="table-row">
              <th class="table-head" data-i18n="pos.customers.invoice">Invoice</th>
              <th class="table-head" data-i18n="common.date">Date</th>
              <th class="table-head" data-i18n="common.total">Total</th>
              <th class="table-head" data-i18n="invoice.paid">Paid</th>
              <th class="table-head" data-i18n="common.balance">Balance</th>
              <th class="table-head" data-i18n="common.status">Status</th>
              <th class="table-head" data-i18n="pos.customers.salesPerson">Sales Person</th>
              <th class="table-head" data-i18n="common.store">Store</th>
              <th class="table-head" data-i18n="common.action">Action</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@detail.purchases == []} class="table-row">
              <td class="table-cell muted" colspan="9" data-i18n="pos.customers.noPurchases">
                No purchases found for this customer.
              </td>
            </tr>
            <%= for purchase <- @detail.purchases do %>
              <tr class="table-row">
                <td class="table-cell">{value(purchase, :sequence) || "##{value(purchase, :id)}"}</td>
                <td class="table-cell">{customer_date(value(purchase, :date_create))}</td>
                <td class="table-cell numeric">{money(float(value(purchase, :amount)))}</td>
                <td class="table-cell numeric">{money(float(value(purchase, :total_paid)))}</td>
                <td class="table-cell numeric">
                  {money(max(float(value(purchase, :due_balance)), 0.0))}
                </td>
                <td class="table-cell">{dash(value(purchase, :invoice_status))}</td>
                <td class="table-cell">{dash(value(purchase, :salesperson))}</td>
                <td class="table-cell">{dash(value(purchase, :store_id))}</td>
                <td class="table-cell">
                  <.link
                    class="btn"
                    data-variant="ghost"
                    navigate={invoice_path(customer.name || "", @store_id)}
                  >
                    <span data-i18n="common.view">View</span>
                  </.link>
                </td>
              </tr>
              <tr :if={memo?(purchase)} class="table-row invoice-details-row">
                <td class="table-cell" colspan="9">
                  <section class="card invoice-details-card">
                    <div class="card-content">
                      <section class="invoice-memo" aria-label="Sale memo">
                        <p class="invoice-memo-text">
                          {String.trim(value(purchase, :additional_info))}
                        </p>
                        <div class="invoice-memo-salesperson">
                          <.memo_avatar author={memo_author(purchase)} />
                          {memo_author_name(purchase)}
                        </div>
                      </section>
                    </div>
                  </section>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :numeric, :boolean, default: false

  def summary_card(assigns) do
    ~H"""
    <article class="card">
      <div class="card-header">
        <p class="card-title">{@title}</p>
      </div>
      <div class="card-content">
        <p class={["invoice-kpi-value", @numeric && "numeric"]}>{@value}</p>
      </div>
    </article>
    """
  end

  attr :author, :map, default: nil

  def memo_avatar(assigns) do
    ~H"""
    <span class="avatar invoice-memo-avatar">
      <img :if={avatar_image?(@author)} class="avatar-image" src={value(@author, :pic)} alt="" />
      <span :if={!avatar_image?(@author)}>{memo_author_initial(@author)}</span>
    </span>
    """
  end

  attr :status, :string, default: ""
  attr :saving, :boolean, default: false
  attr :customer, :map, default: nil

  def customer_dialog(assigns) do
    ~H"""
    <% editing? = !is_nil(@customer) %>
    <dialog
      id="customer-dialog"
      class="dialog"
      role="dialog"
      aria-modal="true"
      aria-labelledby="customer-dialog-title"
      phx-hook="CustomerDialog"
    >
      <div class="dialog-content">
        <div class="dialog-header">
          <h2
            id="customer-dialog-title"
            class="dialog-title"
            data-i18n={
              if editing?, do: "pos.customers.editCustomer", else: "pos.customers.createCustomer"
            }
          >
            {if editing?, do: "Edit customer", else: "Create customer"}
          </h2>
          <p
            class="dialog-description"
            data-i18n={
              if editing?, do: "pos.customers.editDialogCopy", else: "pos.customers.addDialogCopy"
            }
          >
            {if editing?,
              do: "Update this customer's account and contact details.",
              else: "Add a customer, then use them on this sale."}
          </p>
        </div>
        <form
          id="customer-form"
          class="form"
          phx-submit={if editing?, do: "update_customer", else: "create_customer"}
        >
          <input :if={editing?} type="hidden" name="customer_id" value={value(@customer, :id)} />
          <div class="form-field">
            <label class="label" for="customer-name" data-i18n="common.name">Name</label>
            <input
              id="customer-name"
              class="input"
              name="name"
              value={value(@customer, :name)}
              required
              autocomplete="name"
            />
          </div>
          <div class="form-field">
            <label class="label" for="customer-document-id" data-i18n="common.documentId">
              Document ID
            </label>
            <input
              id="customer-document-id"
              class="input"
              name="document_id"
              value={value(@customer, :document_id)}
              maxlength="30"
              autocomplete="off"
            />
          </div>
          <div class="form-field">
            <label class="label" for="customer-address" data-i18n="pos.customers.address">
              Address
            </label>
            <input
              id="customer-address"
              class="input"
              name="address"
              value={value(@customer, :address)}
              autocomplete="street-address"
            />
          </div>
          <div class="form-field">
            <label class="label" for="customer-phone" data-i18n="common.phone">Phone</label>
            <input
              id="customer-phone"
              class="input"
              name="celphone"
              value={value(@customer, :celphone)}
              type="tel"
              autocomplete="tel"
            />
          </div>
          <div class="form-field">
            <label class="label" for="customer-email" data-i18n="common.email">Email</label>
            <input
              id="customer-email"
              class="input"
              name="email"
              value={value(@customer, :email)}
              type="email"
              autocomplete="email"
            />
          </div>
          <div class="form-field-inline">
            <input type="hidden" name="is_wholesaler" value="false" />
            <input
              id="customer-is-wholesaler"
              class="checkbox"
              name="is_wholesaler"
              type="checkbox"
              checked={wholesale?(@customer)}
            />
            <label
              class="label"
              for="customer-is-wholesaler"
            >
              <span data-i18n="pos.customers.isWholesaler">Is wholesaler</span>
            </label>
          </div>
          <p id="customer-form-status" class="field-error" role="alert" hidden={@status == ""}>
            {@status}
          </p>
          <div class="dialog-footer">
            <button class="btn" type="button" data-variant="outline" phx-click="close_customer_dialog">
              <span data-i18n="common.cancel">Cancel</span>
            </button>
            <button
              id="customer-submit"
              class="btn"
              type="submit"
              data-variant="default"
              disabled={@saving}
            ><span data-i18n="pos.customers.saveCustomer">Save customer</span></button>
          </div>
        </form>
      </div>
    </dialog>
    """
  end

  defp dash(nil), do: "—"
  defp dash(""), do: "—"
  defp dash(value), do: value
  defp dash(nil, fallback), do: fallback
  defp dash("", fallback), do: fallback
  defp dash(value, _fallback), do: value

  defp wholesale?(customer),
    do: float(value(customer, :wholesaler)) == 1.0 or value(customer, :is_wholesaler) == true

  defp date_only(nil), do: "—"
  defp date_only(%NaiveDateTime{} = value), do: Calendar.strftime(value, "%-m/%-d/%Y")

  defp date_only(value) when is_binary(value) do
    case value |> String.replace(" ", "T") |> NaiveDateTime.from_iso8601() do
      {:ok, date} -> date_only(date)
      _ -> "—"
    end
  end

  defp date_only(_), do: "—"
  defp customer_date(%NaiveDateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M")
  defp customer_date(nil), do: "—"

  defp customer_date(value) when is_binary(value) do
    case value |> String.replace(" ", "T") |> NaiveDateTime.from_iso8601() do
      {:ok, date} -> customer_date(date)
      _ -> "—"
    end
  end

  defp customer_date(_), do: "—"
  defp store_path(path, nil), do: path
  defp store_path(path, ""), do: path
  defp store_path(path, store_id), do: path <> "?" <> URI.encode_query(%{"store_id" => store_id})
  defp invoice_path(search, nil), do: ~p"/pos/invoices?search=#{search}"
  defp invoice_path(search, ""), do: ~p"/pos/invoices?search=#{search}"
  defp invoice_path(search, store_id), do: ~p"/pos/invoices?#{%{search: search, store_id: store_id}}"
  defp memo?(purchase), do: String.trim(to_string(value(purchase, :additional_info) || "")) != ""

  defp memo_author(purchase),
    do: value(purchase, :memo_author) || %{name: value(purchase, :salesperson)}

  defp memo_author_name(purchase) do
    author = memo_author(purchase)
    dash(value(author, :name) || value(author, :username) || value(purchase, :salesperson))
  end

  defp memo_author_initial(author) do
    author
    |> then(&(value(&1, :name) || value(&1, :username) || "?"))
    |> String.first()
  end

  defp avatar_image?(author), do: value(author, :pic) not in [nil, ""]
  defp float(value) when is_number(value), do: value * 1.0
  defp float(%Decimal{} = value), do: Decimal.to_float(value)

  defp float(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> number
      _ -> 0.0
    end
  end

  defp float(_), do: 0.0
  defp value(nil, _key), do: nil
  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
