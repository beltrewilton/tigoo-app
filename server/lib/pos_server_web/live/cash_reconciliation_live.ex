defmodule TigooServerWeb.CashReconciliationLive do
  @moduledoc false
  use TigooServerWeb, :live_view

  import Ecto.Query
  import TigooServerWeb.PosLayoutComponents

  alias TigooServer.{Authentication, Repo, TenantContext}
  alias TigooServer.Accounts.{Company, UserCompany}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.{InventoryContext, Sale, SalePaid, User}

  @payment_labels %{"CASH" => "Cash payments", "CC" => "Credit/debit card payments"}

  @impl true
  def mount(params, session, socket) do
    today = Date.to_iso8601(server_today())

    with token when is_binary(token) <- session["user_token"],
         {:ok, scope} <- Authentication.authenticate(token),
         true <- Scope.allowed?(scope, "pos.reconciliation"),
         _ <- TenantContext.put_tenant(scope.tenant),
         {:ok, stores} <- InventoryContext.stores(scope),
         %{id: store_id} <- selected_store(stores, Map.get(params, "store_id") || session["store_id"]) do
      cashiers = cashiers(scope)
      cashier = List.first(cashiers)

      socket =
        socket
        |> assign(:page_title, gettext("Cash Reconciliation"))
        |> assign(:print_relay_token, token)
        |> assign(:scope, scope)
        |> assign(:stores, stores)
        |> assign(:store_id, store_id)
        |> assign(:cashiers, cashiers)
        |> assign(:cashier, cashier && cashier.username)
        |> assign(:date, today)
        |> assign(:opening_cash, "0.00")
        |> assign(:summary, empty_summary())
        |> assign(:receipt, nil)
        |> assign(:print_prompt, nil)
        |> refresh_reconciliation()

      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Cash reconciliation access is required.")
         |> redirect(to: ~p"/pos/login")}
    end
  end

  @impl true
  def handle_event("change_store", %{"store_id" => id}, socket) do
    with {store_id, ""} <- Integer.parse(id),
         true <- Enum.any?(socket.assigns.stores, &(&1.id == store_id)),
         {:ok, _} <- InventoryContext.authorize_store(socket.assigns.scope, store_id) do
      {:noreply, socket |> assign(:store_id, store_id) |> refresh_reconciliation()}
    else
      _ -> {:noreply, put_flash(socket, :error, "The selected store is unavailable.")}
    end
  end

  def handle_event("restore_pos_draft", _draft, socket), do: {:noreply, socket}
  def handle_event("set_catalog_view", _params, socket), do: {:noreply, socket}
  def handle_event("client_info", _params, socket), do: {:noreply, socket}

  def handle_event("change_filters", params, socket) do
    {:noreply,
     socket
     |> assign(:cashier, Map.get(params, "cashier", socket.assigns.cashier))
     |> assign(:date, Map.get(params, "date", socket.assigns.date))
     |> assign(:opening_cash, Map.get(params, "opening_cash", socket.assigns.opening_cash))
     |> refresh_reconciliation()}
  end

  def handle_event("print_reconciliation", _params, socket) do
    {:noreply,
     assign(socket, :print_prompt, %{
       title: "Print reconciliation",
       title_key: "reconciliation.printTitle",
       description: "Print the cash reconciliation receipt.",
       description_key: "reconciliation.printDescription",
       button: "Print report",
       button_key: "reconciliation.printReport",
       event: "printer:print-reconciliation",
       payload: %{request_id: print_request_id(), reconciliation: socket.assigns.receipt}
     })}
  end

  def handle_event("printer_status", _params, socket), do: {:noreply, socket}
  def handle_event("printer_result", %{"status" => "success"}, socket), do: {:noreply, assign(socket, :print_prompt, nil)}
  def handle_event("printer_result", %{"message" => message}, socket), do: {:noreply, update_print_prompt(socket, "Print failed: #{message}", false)}
  def handle_event("printer_result", _params, socket), do: {:noreply, update_print_prompt(socket, "Print failed.", false)}
  def handle_event("skip_print", _params, socket), do: {:noreply, assign(socket, :print_prompt, nil)}
  def handle_event("confirm_print", _params, %{assigns: %{print_prompt: nil}} = socket), do: {:noreply, socket}

  def handle_event("confirm_print", _params, socket) do
    prompt = socket.assigns.print_prompt
    {:noreply, socket |> update_print_prompt("Printing...", true) |> push_event(prompt.event, prompt.payload)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.pos_layout id="cash-reconciliation-live" active_page={:reconciliation} scope={@scope} stores={@stores} store_id={@store_id} print_relay_token={@print_relay_token} phx-hook="PosShell">
      <section class="catalog-panel reconciliation-panel" aria-labelledby="reconciliation-title">
        <header class="topbar invoice-topbar">
          <div class="brand-lockup">
            <span class="brand-mark">T</span>
            <div>
              <p class="eyebrow">Tigoo</p>
              <h1 id="reconciliation-title" class="h3" tabindex="-1" data-i18n="reconciliation.title">Cash Reconciliation</h1>
            </div>
          </div>
          <button class="btn" type="button" data-variant="default" phx-click="print_reconciliation">
            <span data-i18n="reconciliation.printReport">Print report</span>
          </button>
        </header>

        <section class="reconciliation-controls" aria-labelledby="reconciliation-controls-title">
          <h2 id="reconciliation-controls-title" class="card-title" data-i18n="reconciliation.registerInputs">Register inputs</h2>
          <form class="form" phx-change="change_filters">
            <div class="form-group">
              <label class="label" for="reconciliation-cashier" data-i18n="reconciliation.cashier">Cashier</label>
              <select id="reconciliation-cashier" class="select" name="cashier">
                <option :for={cashier <- @cashiers} value={cashier.username} selected={cashier.username == @cashier}>
                  {cashier_name(cashier)}
                </option>
              </select>
            </div>
            <div class="form-group">
              <label class="label" for="reconciliation-date" data-i18n="common.date">Date</label>
              <input id="reconciliation-date" class="input" type="date" name="date" value={@date} />
            </div>
            <div class="form-group">
              <label class="label" for="reconciliation-opening-cash" data-i18n="reconciliation.openingCash">Opening cash</label>
              <input id="reconciliation-opening-cash" class="input numeric" type="number" name="opening_cash" min="0" step="0.01" inputmode="decimal" value={@opening_cash} />
            </div>
          </form>

          <dl class="totals reconciliation-totals">
            <div><dt data-i18n="reconciliation.salesCount">Sales count</dt><dd>{@summary.sale_count}</dd></div>
            <div><dt data-i18n="reconciliation.cashPayments">Cash payments</dt><dd>{money(payment_total(@summary, "CASH"))}</dd></div>
            <div><dt data-i18n="reconciliation.cardPayments">Credit/debit card payments</dt><dd>{money(payment_total(@summary, "CC"))}</dd></div>
            <div><dt data-i18n="reconciliation.totalSales">Total sales</dt><dd>{money(@summary.total_sales)}</dd></div>
            <div class="grand-total"><dt data-i18n="reconciliation.expectedCashDrawer">Expected cash drawer</dt><dd>{money(@summary.expected_cash)}</dd></div>
          </dl>
        </section>
      </section>

      <aside id="order-panel" class="order-panel reconciliation-receipt-panel" aria-labelledby="reconciliation-preview-title">
        <header class="order-header">
          <div>
            <p class="eyebrow" data-i18n="reconciliation.reportPreview">Report preview</p>
            <h2 id="reconciliation-preview-title" class="h3" data-i18n="reconciliation.receipt">Receipt</h2>
          </div>
        </header>
        <div class="receipt-preview-scroll">
          <pre class="receipt-preview">{receipt_text(@receipt)}</pre>
        </div>
      </aside>

      <.print_dialog :if={@print_prompt} prompt={@print_prompt} />
    </.pos_layout>
    """
  end

  defp refresh_reconciliation(socket) do
    date = date_filter(socket.assigns.date)
    opening_cash = decimal(socket.assigns.opening_cash)

    filters = %{
      "store_id" => socket.assigns.store_id,
      "cashier" => socket.assigns.cashier,
      "date_from" => date && NaiveDateTime.new!(date, ~T[00:00:00]),
      "date_to" => date && NaiveDateTime.new!(date, ~T[23:59:59])
    }

    summary =
      if filters["date_from"] && filters["date_to"] && filters["cashier"] do
        socket.assigns.scope.tenant
        |> reconciliation_sales(filters)
        |> summarize_sales(opening_cash)
      else
        empty_summary(opening_cash)
      end

    assign(socket, summary: summary, receipt: receipt_payload(socket, summary))
  end

  defp summarize_sales(sales, opening_cash) do
    active_sales = Enum.reject(sales, &(value(&1, :status) == "RETURN"))
    payment_totals = Enum.reduce(active_sales, %{}, &sum_payments/2)
    cash_payments = Map.get(payment_totals, "CASH", 0.0)
    total_paid = Enum.reduce(payment_totals, 0.0, fn {_type, amount}, total -> total + amount end)

    %{
      sale_count: length(active_sales),
      sales: Enum.map(active_sales, &sale_receipt_row/1),
      total_sales: total_paid,
      total_paid: total_paid,
      payment_totals: payment_totals,
      opening_cash: opening_cash,
      expected_cash: opening_cash + cash_payments
    }
  end

  defp sum_payments(sale, acc) do
    Enum.reduce(value(sale, :sale_paids) || value(sale, :payments) || [], acc, fn payment, totals ->
      type = value(payment, :type) || "OTHER"
      Map.update(totals, type, decimal(value(payment, :amount)), &(decimal(value(payment, :amount)) + &1))
    end)
  end

  defp reconciliation_sales(tenant, filters) do
    payments_query = from(payment in SalePaid, order_by: [asc: payment.date_create, asc: payment.id])

    Sale
    |> join(:left, [sale], client in assoc(sale, :client))
    |> where([sale], sale.store_id == ^filters["store_id"])
    |> where([sale], sale.login == ^filters["cashier"])
    |> where([sale], sale.date_create >= ^filters["date_from"])
    |> where([sale], sale.date_create <= ^filters["date_to"])
    |> order_by([sale], asc: sale.date_create, asc: sale.id)
    |> preload([_sale, client], client: client, sale_paids: ^payments_query)
    |> Repo.all(prefix: tenant)
  end

  defp receipt_payload(socket, summary) do
    cashier = selected_cashier(socket)

    %{
      type: "reconciliation",
      company_name: company_name(socket.assigns.scope, current_store(socket)),
      cashier: cashier_full_name(cashier),
      date: socket.assigns.date,
      generated_at: receipt_datetime(server_now()),
      store: current_store(socket),
      opening_cash: summary.opening_cash,
      sales: summary.sales,
      sales_count: summary.sale_count,
      total_sales: summary.total_sales,
      total_paid: summary.total_paid,
      expected_cash: summary.expected_cash,
      payment_totals:
        summary.payment_totals
        |> Enum.sort_by(fn {type, _amount} -> type end)
        |> Enum.map(fn {type, amount} -> %{type: type, label: payment_label(type), amount: amount} end)
    }
  end

  defp receipt_text(nil), do: ""

  defp receipt_text(receipt) do
    lines = [
      center(receipt.company_name),
      center("CASH RECONCILIATION"),
      rule(),
      row("Cashier", receipt.cashier),
      row("Printed at", receipt.generated_at),
      row("Opening cash", money_text(receipt.opening_cash)),
      rule(),
      "SALES",
      rule()
    ]

    sale_lines =
      receipt.sales
      |> Enum.flat_map(fn sale ->
        [
          row(sale.customer_name, money_text(sale.amount)),
          sale.date
        ]
      end)

    payment_lines = Enum.map(receipt.payment_totals, &row(&1.label, money_text(&1.amount)))

    (lines ++
       sale_lines ++
       [
         rule(),
         row("Sales count", receipt.sales_count),
         row("Total sales", money_text(receipt.total_sales)),
         rule()
       ] ++ payment_lines ++ [rule(), row("Expected drawer", money_text(receipt.expected_cash))])
    |> Enum.join("\n")
  end

  defp print_dialog(assigns) do
    ~H"""
    <dialog id="receipt-dialog" class="dialog" data-size="sm" open role="dialog" aria-modal="true" aria-labelledby="receipt-dialog-title">
      <div class="dialog-content">
        <div class="dialog-header">
          <h2 id="receipt-dialog-title" class="dialog-title" data-i18n={@prompt[:title_key]}>
            {@prompt.title}
          </h2>
          <p
            id="receipt-print-description"
            class="dialog-description"
            data-i18n={@prompt[:description_key]}
          >
            {@prompt.description}
          </p>
        </div>
        <p id="receipt-print-status" class="print-status" role="status">{@prompt[:status] || ""}</p>
        <div class="dialog-footer">
          <button id="skip-print" class="btn" type="button" data-variant="outline" phx-click="skip_print" disabled={@prompt[:printing] == true}>
            <span data-i18n="common.cancel">Cancel</span>
          </button><button id="print-receipt" class="btn" type="button" data-variant="default" phx-click="confirm_print" disabled={@prompt[:printing] == true}>
            <span data-i18n={@prompt[:button_key]}>{@prompt.button}</span>
          </button>
        </div>
      </div>
    </dialog>
    """
  end

  defp cashiers(scope) do
    Repo.all(from(user in User, where: user.is_active == 1, order_by: [asc: user.username]), prefix: scope.tenant)
  end

  defp selected_store(stores, selected_id) do
    Enum.find(stores, &(to_string(&1.id) == to_string(selected_id))) || List.first(stores)
  end

  defp current_store(socket), do: Enum.find(socket.assigns.stores, &(&1.id == socket.assigns.store_id))
  defp company_name(%{actor: :admin, actor_id: user_id, tenant: tenant}, store) do
    case Repo.one(
           from(company in Company,
             join: membership in UserCompany,
             on: membership.company_id == company.id,
             where: membership.user_id == ^user_id,
             select: company.company_name,
             limit: 1
           ),
           prefix: tenant
         ) do
      nil -> store_name(store)
      name -> name |> to_string() |> String.upcase()
    end
  end

  defp company_name(_scope, store), do: store_name(store)
  defp store_name(nil), do: "TIGOO"
  defp store_name(store), do: (value(store, :name) || "TIGOO") |> to_string() |> String.upcase()
  defp empty_summary(opening_cash \\ 0.0), do: %{sale_count: 0, sales: [], total_sales: 0.0, total_paid: 0.0, payment_totals: %{}, opening_cash: opening_cash, expected_cash: opening_cash}
  defp payment_total(summary, type), do: Map.get(summary.payment_totals, type, 0.0)
  defp payment_label(type), do: Map.get(@payment_labels, type, "#{type} payments")
  defp cashier_name(user) do
    name =
      [user.first_name, user.last_name]
      |> Enum.reject(&blank?/1)
      |> Enum.join(" ")

    if name == "", do: user.username, else: "#{name} (#{user.username})"
  end
  defp cashier_full_name(nil), do: ""
  defp cashier_full_name(user) do
    [user.first_name, user.last_name]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
    |> then(fn name -> if name == "", do: user.username, else: name end)
    |> String.upcase()
  end

  defp selected_cashier(socket), do: Enum.find(socket.assigns.cashiers, &(&1.username == socket.assigns.cashier))
  defp sale_receipt_row(sale) do
    %{
      customer_name: sale_customer_name(sale),
      date: receipt_datetime(received_at(sale) || value(sale, :date_create)),
      amount: received_amount(sale)
    }
  end

  defp received_amount(sale) do
    sale
    |> value(:sale_paids)
    |> List.wrap()
    |> Enum.reduce(0.0, &(decimal(value(&1, :amount)) + &2))
  end

  defp received_at(sale) do
    sale
    |> value(:sale_paids)
    |> List.wrap()
    |> Enum.map(&value(&1, :date_create))
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(nil, fn date, latest ->
      if is_nil(latest) || NaiveDateTime.compare(date, latest) == :gt, do: date, else: latest
    end)
  end

  defp sale_customer_name(sale) do
    case value(value(sale, :client) || %{}, :name) do
      nil -> "CUSTOMER"
      name -> name |> to_string() |> String.upcase()
    end
  end

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""
  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp print_request_id, do: "print-#{System.unique_integer([:positive])}"
  defp server_today do
    {{year, month, day}, _time} = :calendar.local_time()
    Date.new!(year, month, day)
  end
  defp server_now do
    {{year, month, day}, {hour, minute, second}} = :calendar.local_time()
    NaiveDateTime.new!(year, month, day, hour, minute, second)
  end
  defp date_filter(value) do
    case Date.from_iso8601(to_string(value || "")) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp decimal(%Decimal{} = v), do: Decimal.to_float(v)
  defp decimal(v) when is_number(v), do: v * 1.0

  defp decimal(v) when is_binary(v) do
    case Float.parse(v) do
      {number, _} -> number
      :error -> 0.0
    end
  end

  defp decimal(_), do: 0.0
  defp receipt_datetime(%NaiveDateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %I:%M %p")
  defp receipt_datetime(_), do: ""
  defp center(value), do: String.pad_leading(to_string(value), div(48 + String.length(to_string(value)), 2))
  defp row(label, value), do: "#{label}#{String.duplicate(" ", max(1, 48 - String.length(to_string(label)) - String.length(to_string(value))))}#{value}"
  defp rule, do: String.duplicate("-", 48)
  defp update_print_prompt(%{assigns: %{print_prompt: nil}} = socket, _status, _printing), do: socket
  defp update_print_prompt(socket, status, printing),
    do: Phoenix.Component.update(socket, :print_prompt, &Map.merge(&1, %{status: status, printing: printing}))
end
