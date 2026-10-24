defmodule TigooServerWeb.InvoiceReportLive do
  @moduledoc false
  use TigooServerWeb, :live_view

  import TigooServerWeb.PosLayoutComponents

  alias TigooServer.{Authentication, TenantContext}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.{InventoryContext, Sales, Sql}

  @sort_keys ~w(sequence client_name date_create due_date invoice_status amount due_balance login)
  @statuses ~w(open close cancelled)

  @impl true
  def mount(params, session, socket) do
    today = server_today()

    with token when is_binary(token) <- session["user_token"],
         {:ok, scope} <- Authentication.authenticate(token),
         true <- Scope.allowed?(scope, "sales.view"),
         _ <- TenantContext.put_tenant(scope.tenant),
         {:ok, stores} <- InventoryContext.stores(scope),
         %{id: store_id} <- selected_store(stores, Map.get(params, "store_id") || session["store_id"]) do
      {:ok,
       socket
       |> assign(:page_title, gettext("Invoice Report"))
       |> assign(:print_relay_token, token)
       |> assign(:scope, scope)
       |> assign(:stores, stores)
       |> assign(:store_id, store_id)
       |> assign(:entries, [])
       |> assign(:summary, %{})
       |> assign(:cursor, nil)
       |> assign(:has_more?, true)
       |> assign(:loading?, false)
       |> assign(:load_error?, false)
       |> assign(:search, Map.get(params, "search", ""))
       |> assign(:date_from, Date.to_iso8601(today))
       |> assign(:date_to, Date.to_iso8601(today))
       |> assign(:status_filter, "")
       |> assign(:sort, %{key: "date_create", direction: :desc})
       |> assign(:expanded_id, nil)
       |> assign(:details, %{})
       |> assign(:payment_methods, %{})
       |> assign(:payment_amounts, %{})
       |> assign(:calendar_open?, false)
       |> assign(:calendar_month, month_start(today))
       |> assign(:pending_range, %{from: Date.to_iso8601(today), to: Date.to_iso8601(today)})
       |> assign(:cancel_id, nil)
       |> assign(:print_prompt, nil)
       |> assign(:status, "Loading invoices…")
       |> load_page(true)}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Sales-report access is required.")
         |> redirect(to: ~p"/pos/login")}
    end
  end

  @impl true
  def handle_event("change_store", %{"store_id" => id}, socket) do
    with {store_id, ""} <- Integer.parse(id),
         true <- Enum.any?(socket.assigns.stores, &(&1.id == store_id)),
         {:ok, _} <- InventoryContext.authorize_store(socket.assigns.scope, store_id) do
      {:noreply, socket |> assign(:store_id, store_id) |> reset_report() |> load_page(true)}
    else
      _ -> {:noreply, put_flash(socket, :error, "The selected store is unavailable.")}
    end
  end

  def handle_event("search", %{"search" => value}, socket),
    do: {:noreply, socket |> assign(:search, value) |> reset_report() |> load_page(true)}

  def handle_event("apply_filters", params, socket),
    do:
      {:noreply,
       socket
       |> assign(:search, Map.get(params, "search", socket.assigns.search))
       |> reset_report()
       |> load_page(true)}

  def handle_event("clear_filters", _, socket) do
    {:noreply,
     socket
     |> assign(search: "", date_from: "", date_to: "", status_filter: "")
     |> reset_report()
     |> load_page(true)}
  end

  def handle_event("toggle_status", %{"status" => status}, socket) when status in @statuses do
    status = if socket.assigns.status_filter == status, do: "", else: status
    {:noreply, socket |> assign(:status_filter, status) |> reset_report() |> load_page(true)}
  end

  def handle_event("sort", %{"key" => key}, socket) when key in @sort_keys do
    sort =
      if socket.assigns.sort.key == key,
        do: %{key: key, direction: flip(socket.assigns.sort.direction)},
        else: %{key: key, direction: :asc}

    {:noreply, socket |> assign(:sort, sort) |> update(:entries, &sort_entries(&1, sort))}
  end

  def handle_event("load_more", _, socket), do: {:noreply, load_page(socket, false)}

  def handle_event("toggle_detail", %{"id" => id}, socket) do
    id = integer(id)

    cond do
      socket.assigns.expanded_id == id ->
        {:noreply, assign(socket, :expanded_id, nil)}

      Map.has_key?(socket.assigns.details, id) ->
        {:noreply, assign(socket, :expanded_id, id)}

      true ->
        socket = assign(socket, :expanded_id, id)

        case Sales.get_sale(socket.assigns.scope, id) do
          {:ok, detail} ->
            {:noreply, assign(socket, :details, Map.put(socket.assigns.details, id, detail))}

          _ ->
            {:noreply,
             socket
             |> assign(:expanded_id, nil)
             |> put_flash(:error, "Invoice details could not be loaded.")}
        end
    end
  end

  def handle_event("select_payment_method", %{"id" => id, "row" => row, "type" => type}, socket)
      when type in ["CASH", "CC"] do
    {:noreply,
     assign(
       socket,
       :payment_methods,
       Map.put(socket.assigns.payment_methods, {integer(id), row}, type)
     )}
  end

  def handle_event("change_payment_amount", %{"_id" => id, "amount" => amount}, socket) do
    {:noreply,
     assign(
       socket,
       :payment_amounts,
       Map.put(socket.assigns.payment_amounts, integer(id), amount)
     )}
  end

  def handle_event("add_payment", %{"_id" => id, "amount" => amount, "row" => row}, socket) do
    id = integer(id)
    invoice = Enum.find(socket.assigns.entries, &(integer(value(&1, "id")) == id))

    amount =
      if row == "payoff", do: decimal(value(invoice || %{}, "due_balance")), else: decimal(amount)

    type = Map.get(socket.assigns.payment_methods, {id, row}, "CASH")

    if invoice && amount > 0 && amount <= decimal(value(invoice, "due_balance")) do
      case Sales.add_payment(socket.assigns.scope, id, %{"amount" => amount, "type" => type}) do
        {:ok, detail} ->
          {:noreply,
           socket
           |> replace_invoice(detail)
           |> refresh_summary()
           |> update(:payment_amounts, &Map.delete(&1, id))
           |> put_flash(:info, "Payment recorded.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Payment could not be recorded: #{reason}")}
      end
    else
      # Tauri simply keeps the payment form unchanged when its client-side
      # amount guard fails; it does not show a report-level error.
      {:noreply, socket}
    end
  end

  def handle_event("open_cancel", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :cancel_id, integer(id))}

  def handle_event("close_cancel", _, socket), do: {:noreply, assign(socket, :cancel_id, nil)}

  def handle_event("confirm_cancel", _, %{assigns: %{cancel_id: id}} = socket)
      when is_integer(id) do
    case Sales.cancel_sale(socket.assigns.scope, id) do
      {:ok, detail} ->
        {:noreply,
         socket
         |> replace_invoice(detail)
         |> refresh_summary()
         |> assign(:cancel_id, nil)
         |> put_flash(:info, "Invoice cancelled.")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:cancel_id, nil)
         |> put_flash(:error, "Invoice could not be cancelled: #{reason}")}
    end
  end

  def handle_event("reprint_invoice", %{"id" => id}, socket) do
    id = integer(id)

    case Map.get(socket.assigns.details, id) || Sales.get_sale(socket.assigns.scope, id) do
      {:ok, detail} ->
        {:noreply,
         assign(socket, :print_prompt, print_prompt(:invoice, printable_detail(detail, socket)))}

      detail when is_map(detail) ->
        {:noreply,
         assign(socket, :print_prompt, print_prompt(:invoice, printable_detail(detail, socket)))}

      _ ->
        {:noreply, put_flash(socket, :error, "Invoice details could not be loaded.")}
    end
  end

  def handle_event(
        "print_payment",
        %{"invoice_id" => invoice_id, "payment_id" => payment_id},
        socket
      ) do
    invoice_id = integer(invoice_id)
    payment_id = integer(payment_id)

    with detail when is_map(detail) <- Map.get(socket.assigns.details, invoice_id),
         payment when is_map(payment) <-
           Enum.find(detail.payments || [], &(integer(value(&1, :id)) == payment_id)) do
      {:noreply,
       assign(
         socket,
         :print_prompt,
         print_prompt(:payment, printable_detail(detail, socket), payment)
       )}
    else
      _ -> {:noreply, put_flash(socket, :error, "Payment details could not be loaded.")}
    end
  end

  def handle_event("printer_status", _params, socket), do: {:noreply, socket}

  def handle_event("printer_result", %{"status" => "success"}, socket),
    do: {:noreply, assign(socket, :print_prompt, nil)}

  def handle_event("printer_result", %{"message" => message}, socket),
    do: {:noreply, update_print_prompt(socket, "Print failed: #{message}", false)}

  def handle_event("printer_result", _params, socket),
    do: {:noreply, update_print_prompt(socket, "Print failed.", false)}

  def handle_event("skip_print", _params, socket),
    do: {:noreply, assign(socket, :print_prompt, nil)}

  def handle_event("confirm_print", _params, %{assigns: %{print_prompt: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("confirm_print", _params, socket) do
    prompt = socket.assigns.print_prompt

    {:noreply,
     socket
     |> update_print_prompt("Printing…", true)
     |> push_event(prompt.event, prompt.payload)}
  end

  def handle_event("open_calendar", _, socket) do
    today = Date.to_iso8601(server_today())

    range =
      if socket.assigns.date_from == "" and socket.assigns.date_to == "",
        do: %{from: today, to: ""},
        else: %{from: socket.assigns.date_from, to: socket.assigns.date_to}

    month =
      if range.from != "",
        do: month_start(Date.from_iso8601!(range.from)),
        else: month_start(server_today())

    {:noreply, assign(socket, calendar_open?: true, pending_range: range, calendar_month: month)}
  end

  def handle_event("close_calendar", _, socket),
    do: {:noreply, assign(socket, :calendar_open?, false)}

  def handle_event("calendar_month", %{"direction" => direction}, socket)
      when direction in ["previous", "next"] do
    month =
      if direction == "previous",
        do: Date.add(socket.assigns.calendar_month, -1) |> month_start(),
        else: month_end(socket.assigns.calendar_month) |> Date.add(1) |> month_start()

    {:noreply, assign(socket, :calendar_month, month)}
  end

  def handle_event("select_date", %{"date" => date}, socket) do
    %{from: from, to: to} = socket.assigns.pending_range

    range =
      cond do
        from == "" or to != "" -> %{from: date, to: ""}
        date < from -> %{from: date, to: from}
        true -> %{from: from, to: date}
      end

    {:noreply, assign(socket, :pending_range, range)}
  end

  def handle_event("clear_range", _, socket),
    do:
      {:noreply,
       socket
       |> assign(
         date_from: "",
         date_to: "",
         pending_range: %{from: "", to: ""},
         calendar_open?: false
       )
       |> reset_report()
       |> load_page(true)}

  def handle_event("apply_range", _, socket) do
    range = socket.assigns.pending_range

    {:noreply,
     socket
     |> assign(date_from: range.from, date_to: range.to, calendar_open?: false)
     |> reset_report()
     |> load_page(true)}
  end

  # A filter/status reset deliberately sets loading? before requesting page one.
  # Only block overlapping incremental pagination requests; a reset must fetch.
  defp load_page(%{assigns: %{loading?: true}} = socket, false), do: socket
  defp load_page(%{assigns: %{has_more?: false}} = socket, false), do: socket

  defp load_page(socket, reset?) do
    socket = if reset?, do: reset_report(socket), else: socket

    opts = [
      search: socket.assigns.search,
      date_from: date_filter(socket.assigns.date_from),
      date_to: date_filter(socket.assigns.date_to),
      invoice_status: blank_nil(socket.assigns.status_filter)
    ]

    case {Sql.sales_report_page(socket.assigns.store_id, socket.assigns.cursor, opts),
          Sql.sales_report_summary(socket.assigns.store_id, Keyword.delete(opts, :invoice_status))} do
      {{:ok, page}, {:ok, summary}} ->
        entries = sort_entries(socket.assigns.entries ++ page.entries, socket.assigns.sort)

        socket
        |> assign(
          entries: entries,
          summary: summary,
          cursor: page.next_cursor,
          has_more?: page.has_more?,
          loading?: false,
          load_error?: false,
          status: report_status(page.has_more?, length(entries))
        )

      _ ->
        assign(socket,
          loading?: false,
          load_error?: true,
          status: "Invoices could not be loaded."
        )
    end
  end

  defp reset_report(socket),
    do:
      assign(socket,
        entries: [],
        cursor: nil,
        has_more?: true,
        expanded_id: nil,
        loading?: true,
        load_error?: false,
        status: "Loading invoices…"
      )

  defp refresh_summary(socket) do
    opts = [
      search: socket.assigns.search,
      date_from: date_filter(socket.assigns.date_from),
      date_to: date_filter(socket.assigns.date_to)
    ]

    case Sql.sales_report_summary(socket.assigns.store_id, opts) do
      {:ok, summary} -> assign(socket, :summary, summary)
      _ -> socket
    end
  end

  defp replace_invoice(socket, detail) do
    entry = summary_entry(detail)

    entries =
      socket.assigns.entries
      |> Enum.map(fn current ->
        if integer(value(current, "id")) == detail.id,
          do: Map.merge(current, entry),
          else: current
      end)
      |> Enum.filter(&entry_matches_status_filter?(&1, socket.assigns.status_filter))
      |> sort_entries(socket.assigns.sort)

    expanded_id =
      if entry_matches_status_filter?(entry, socket.assigns.status_filter),
        do: detail.id,
        else: nil

    # Match Tauri's local patch: update the visible row/detail without
    # resetting pagination, filters, or ordering.
    socket
    |> assign(
      entries: entries,
      details: Map.put(socket.assigns.details, detail.id, detail),
      expanded_id: expanded_id,
      status: "Payment recorded."
    )
  end

  defp entry_matches_status_filter?(_entry, ""), do: true

  defp entry_matches_status_filter?(entry, status),
    do: value(entry, "invoice_status") == status

  defp summary_entry(detail),
    do: %{
      "id" => detail.id,
      "sequence" => detail.sequence,
      "client_name" => detail.client && detail.client.name,
      "date_create" => detail.date_create,
      "invoice_status" => detail.invoice_status,
      "amount" => detail.amount,
      "due_balance" => detail.due_balance,
      "login" => detail.login,
      "cancelled_by" => detail.cancelled_by,
      "store_id" => detail.store_id
    }

  defp sort_entries(entries, %{key: key, direction: direction}) do
    Enum.sort_by(
      entries,
      fn entry -> sortable(value(entry, key), key) end,
      if(direction == :asc, do: :asc, else: :desc)
    )
  end

  defp sortable(v, key) when key in ["amount", "due_balance"], do: decimal(v)
  defp sortable(nil, _), do: ""
  defp sortable(v, _), do: to_string(v) |> String.downcase()
  defp flip(:asc), do: :desc
  defp flip(:desc), do: :asc
  defp blank_nil(""), do: nil
  defp blank_nil(value), do: value
  defp date_filter(""), do: nil

  defp date_filter(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp date_filter(%Date{} = value), do: value
  defp date_filter(_), do: nil
  defp integer(v) when is_integer(v), do: v

  defp integer(v) do
    case Integer.parse(to_string(v)) do
      {number, _} -> number
      :error -> 0
    end
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, String.to_atom(key))
  defp decimal(%Decimal{} = v), do: Decimal.to_float(v)
  defp decimal(v) when is_number(v), do: v * 1.0

  defp decimal(v) when is_binary(v) do
    case Float.parse(v) do
      {number, _} -> number
      :error -> 0.0
    end
  end

  defp decimal(_), do: 0.0
  # Tauri renders list dates in separate en-GB date and 12-hour-time spans.
  defp date_only(%Date{} = value), do: Calendar.strftime(value, "%d/%m/%Y")
  defp date_only(%NaiveDateTime{} = value), do: Calendar.strftime(value, "%d/%m/%Y")
  defp date_only(nil), do: "—"

  defp date_only(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} ->
        date_only(date)

      {:error, _} ->
        case NaiveDateTime.from_iso8601(String.replace(value, " ", "T")) do
          {:ok, date_time} -> date_only(date_time)
          _ -> "—"
        end
    end
  end

  defp date_only(_), do: "—"

  defp invoice_due_date(nil), do: "No due date"
  defp invoice_due_date(value), do: date_only(value)

  defp invoice_due_marker_class(%Date{} = value), do: invoice_due_marker_class_for_date(value)

  defp invoice_due_marker_class(invoice) when is_map(invoice) do
    if value(invoice, "invoice_status") == "open",
      do: invoice_due_marker_class(value(invoice, "due_date")),
      else: nil
  end

  defp invoice_due_marker_class(value), do: invoice_due_marker_class_for_date(due_date(value))

  defp invoice_due_marker_class_for_date(nil), do: "invoice-due-marker-none"

  defp invoice_due_marker_class_for_date(date) do
    case Date.diff(date, server_today()) do
      days when days < 0 -> "invoice-due-marker-overdue"
      0 -> "invoice-due-marker-today"
      1 -> "invoice-due-marker-tomorrow"
      days when days <= 3 -> "invoice-due-marker-soon"
      _ -> "invoice-due-marker-later"
    end
  end

  defp invoice_due_marker_width(%Date{} = value), do: invoice_due_marker_width_for_date(value)

  defp invoice_due_marker_width(invoice) when is_map(invoice) do
    if value(invoice, "invoice_status") == "open",
      do: invoice_due_marker_width(value(invoice, "due_date")),
      else: "0"
  end

  defp invoice_due_marker_width(value), do: invoice_due_marker_width_for_date(due_date(value))

  defp invoice_due_marker_width_for_date(nil), do: "5rem"

  defp invoice_due_marker_width_for_date(date) do
    case Date.diff(date, server_today()) do
      days when days <= 0 -> "100%"
      1 -> "90%"
      days when days <= 3 -> "75%"
      days when days <= 7 -> "55%"
      days when days <= 14 -> "35%"
      _ -> "5rem"
    end
  end

  defp due_date(%Date{} = value), do: value

  defp due_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp due_date(_), do: nil

  defp time_only(%NaiveDateTime{} = value), do: twelve_hour_time(value)

  defp time_only(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(String.replace(value, " ", "T")) do
      {:ok, date_time} -> time_only(date_time)
      _ -> "—"
    end
  end

  defp time_only(_), do: "—"

  defp twelve_hour_time(%NaiveDateTime{hour: hour, minute: minute}) do
    period = if hour < 12, do: "AM", else: "PM"
    "#{rem(hour + 11, 12) + 1}:#{String.pad_leading(Integer.to_string(minute), 2, "0")} #{period}"
  end

  defp report_status(true, _), do: "Scroll to load more invoices."
  defp report_status(false, count), do: "#{count} invoices loaded."
  defp status_label("close"), do: "Paid"
  defp status_label("cancelled"), do: "Cancelled"
  defp status_label(_), do: "Pending"
  defp status_label_key("close"), do: "invoice.paid"
  defp status_label_key("cancelled"), do: "invoice.cancelled"
  defp status_label_key(_), do: "invoice.pending"
  defp kpi_label_key("paid"), do: "invoice.paid"
  defp kpi_label_key("pending"), do: "invoice.pending"
  defp kpi_label_key("cancelled"), do: "invoice.cancelled"

  defp sort_aria(%{key: key, direction: direction}, key),
    do: if(direction == :asc, do: "ascending", else: "descending")

  defp sort_aria(_, _), do: "none"

  defp active_store(assigns),
    do:
      Enum.find_value(assigns.stores, "", fn store ->
        if store.id == assigns.store_id, do: store.name
      end)

  defp month_start(%Date{} = date), do: Date.new!(date.year, date.month, 1)

  defp month_end(%Date{} = date),
    do: Date.new!(date.year, date.month, Calendar.ISO.days_in_month(date.year, date.month))

  defp server_today do
    {{year, month, day}, _time} = :calendar.local_time()
    Date.new!(year, month, day)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.pos_layout
      id="invoice-report-live"
      class="pos-shell invoice-view"
      active_page={:invoices}
      scope={@scope}
      stores={@stores}
      store_id={@store_id}
      print_relay_token={@print_relay_token}
      phx-hook="InvoiceReport"
    >
      <:before_layout>
        <svg class="navigation-icon-sprite" aria-hidden="true" focusable="false">
          <symbol
            id="ui-icon-search"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
          >
            <circle cx="11" cy="11" r="6" /><path d="m16 16 4 4" />
          </symbol>
        </svg>
      </:before_layout>
      <section class="catalog-panel" data-view="invoices" aria-labelledby="invoice-report-title">
        <section id="invoice-report" class="invoice-report" aria-labelledby="invoice-report-title">
          <div class="invoice-report-fixed">
            <header class="topbar invoice-topbar">
              <div class="brand-lockup">
                <span class="brand-mark" aria-hidden="true">E</span>
                <div>
                  <p class="eyebrow" data-i18n="invoice.sales">Sales</p>
                  <h2 id="invoice-report-title" tabindex="-1">
                    <span data-i18n="invoice.title">Invoice Report</span> — {active_store(assigns)}
                  </h2>
                </div>
              </div>
              <form id="invoice-filters" class="invoice-filters" phx-submit="apply_filters">
                <div class="search-field">
                  <svg class="search-icon" aria-hidden="true"><use href="#ui-icon-search" /></svg>
                  <input
                    id="invoice-search"
                    name="search"
                    class="input"
                    type="search"
                    value={@search}
                    phx-change="search"
                    phx-debounce="250"
                    aria-label="Search invoices by customer"
                    data-i18n-aria-label="invoice.search"
                    autocomplete="off"
                    placeholder="Search by customer name"
                    data-i18n-placeholder="invoice.searchPlaceholder"
                  />
                  <button
                    :if={@search != ""}
                    class="btn search-clear"
                    type="button"
                    phx-click={JS.push("search", value: %{search: ""})}
                  >
                    ×
                  </button>
                </div>
                <div class="invoice-date-picker">
                  <button
                    id="invoice-date-range-trigger"
                    class="btn invoice-date-range"
                    type="button"
                    data-variant="outline"
                    data-size="sm"
                    aria-haspopup="dialog"
                    aria-expanded={to_string(@calendar_open?)}
                    phx-click="open_calendar"
                  >
                    {range_label(@date_from, @date_to)}
                  </button>
                  <.calendar_popover
                    :if={@calendar_open?}
                    month={@calendar_month}
                    range={@pending_range}
                  />
                </div>
                <button class="btn" type="submit" data-variant="outline" data-size="sm">
                  <span data-i18n="common.apply">Apply</span>
                </button><button
                  id="invoice-filters-clear"
                  class="btn"
                  type="button"
                  data-variant="ghost"
                  data-size="sm"
                  phx-click="clear_filters"
                ><span data-i18n="common.clear">Clear</span></button>
              </form>
            </header>
            <section
              class="invoice-summary"
              aria-label="Invoice status summary"
              data-i18n-aria-label="invoice.summary"
            >
              <.kpi
                name="paid"
                label="Paid"
                status="close"
                summary={@summary}
                selected={@status_filter}
              /><.kpi
                name="pending"
                label="Pending"
                status="open"
                summary={@summary}
                selected={@status_filter}
              /><.kpi
                name="cancelled"
                label="Cancelled"
                status="cancelled"
                summary={@summary}
                selected={@status_filter}
              />
            </section>
            <p id="invoice-report-status" class="invoice-report-status" role="status">{@status}</p>
          </div>
          <div class="table-container invoice-table-container">
            <table class="table invoice-table">
              <caption class="table-caption" data-i18n="invoice.selectedStoreCaption">
                Invoices for the selected store.
              </caption>
              <thead>
                <tr class="table-row">
                  <th
                    :for={{label, key, i18n_key} <- headers()}
                    class="table-head"
                    scope="col"
                    aria-sort={sort_aria(@sort, key)}
                  >
                    <button
                      class="btn invoice-sort"
                      type="button"
                      data-variant="ghost"
                      phx-click="sort"
                      phx-value-key={key}
                    >
                      <span data-i18n={i18n_key}>{label}</span>
                    </button>
                  </th>
                  <th class="table-head" scope="col">
                    <span class="sr-only" data-i18n="common.actions">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody id="invoice-table-body">
                <%= for invoice <- @entries do %>
                  <.invoice_row
                    invoice={invoice}
                    expanded={@expanded_id == integer(value(invoice, "id"))}
                  /><.invoice_detail
                    :if={@expanded_id == integer(value(invoice, "id"))}
                    invoice={invoice}
                    detail={Map.get(@details, integer(value(invoice, "id")))}
                    methods={@payment_methods}
                    amounts={@payment_amounts}
                  />
                <% end %>
              </tbody>
            </table>
          </div>
          <div id="invoice-sentinel" phx-hook="InfiniteInvoices" aria-hidden="true"></div>
        </section>
      </section>
      <.cancel_dialog
        :if={@cancel_id}
        invoice={Enum.find(@entries, &(integer(value(&1, "id")) == @cancel_id))}
      />
      <.print_dialog :if={@print_prompt} prompt={@print_prompt} />
    </.pos_layout>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :status, :string, required: true
  attr :summary, :map, required: true
  attr :selected, :string, required: true

  defp kpi(assigns) do
    ~H"""
    <article class={["card", "invoice-summary-#{@name}"]}>
      <button
        class="btn invoice-kpi"
        type="button"
        data-variant={if @selected == @status, do: "secondary", else: "ghost"}
        phx-click="toggle_status"
        phx-value-status={@status}
        aria-pressed={to_string(@selected == @status)}
      >
        <div class="card-header">
          <p class="card-title" data-i18n={kpi_label_key(@name)}>{@label}</p>
        </div>
        <div class={["card-content", @name == "paid" && "invoice-kpi-content-breakdown"]}>
          <div class="invoice-kpi-metric">
            <p id={"invoice-#{@name}-total"} class="invoice-kpi-value numeric">
              {money(value(@summary, "#{@name}_total"))}
            </p>
            <p id={"invoice-#{@name}-count"} class="invoice-kpi-total muted numeric">
              {value(@summary, "#{@name}_count") || 0}
            </p>
          </div>
          <div :if={@name == "paid"} class="invoice-kpi-metric">
            <p id="invoice-paid-credit-card-total" class="invoice-kpi-value numeric">
              {money(value(@summary, "paid_cc_total"))}
            </p>
            <p class="invoice-kpi-total muted" data-i18n="pos.checkout.creditCard">Credit Card</p>
          </div>
          <div :if={@name == "paid"} class="invoice-kpi-metric">
            <p id="invoice-paid-cash-total" class="invoice-kpi-value numeric">
              {money(value(@summary, "paid_cash_total"))}
            </p>
            <p class="invoice-kpi-total muted" data-i18n="common.cash">Cash</p>
          </div>
        </div>
      </button>
    </article>
    """
  end

  attr :invoice, :map, required: true
  attr :expanded, :boolean, required: true

  defp invoice_row(assigns) do
    id = integer(value(assigns.invoice, "id"))
    assigns = assign(assigns, :id, id)

    ~H"""
    <tr
      class={["table-row", "invoice-row", invoice_due_marker_class(@invoice)]}
      style={"--invoice-due-width: #{invoice_due_marker_width(@invoice)};"}
    >
      <td class="table-cell" data-label="Invoice" data-i18n-data-label="pos.customers.invoice">
        <button
          class="btn invoice-detail-trigger"
          type="button"
          data-variant="ghost"
          phx-click="toggle_detail"
          phx-value-id={@id}
          aria-expanded={to_string(@expanded)}
        >
          <span class="invoice-disclosure" aria-hidden="true">{if @expanded, do: "▾", else: "▸"}</span>{value(
            @invoice,
            "sequence"
          ) || "##{@id}"}
        </button>
      </td>
      <td class="table-cell" data-label="Customer" data-i18n-data-label="pos.checkout.customer">
        <button
          class="btn invoice-detail-trigger"
          type="button"
          data-variant="ghost"
          phx-click="toggle_detail"
          phx-value-id={@id}
          aria-expanded={to_string(@expanded)}
        >
          <span data-i18n={if value(@invoice, "client_name"), do: nil, else: "invoice.walkIn"}>
            {value(@invoice, "client_name") || "Walk-in customer"}
          </span>
        </button>
      </td>
      <td class="table-cell" data-label="Date" data-i18n-data-label="common.date">
        <span class="invoice-date">{date_only(value(@invoice, "date_create"))}</span><span class="invoice-time">{time_only(value(@invoice, "date_create"))}</span>
      </td>
      <td
        class="table-cell invoice-due-date-cell"
        data-label="Due Date"
        data-i18n-data-label="invoice.dueDateHeader"
      >
        <span class="invoice-date">{invoice_due_date(value(@invoice, "due_date"))}</span>
      </td>
      <td class="table-cell" data-label="Status" data-i18n-data-label="common.status">
        <span class={["invoice-status", "invoice-status-#{value(@invoice, "invoice_status")}"]}>
          <span data-i18n={status_label_key(value(@invoice, "invoice_status"))}>
            {status_label(value(@invoice, "invoice_status"))}
          </span>
        </span>
      </td>
      <td class="table-cell numeric" data-label="Total" data-i18n-data-label="common.total">
        {money(value(@invoice, "amount"))}
      </td>
      <td class="table-cell numeric" data-label="Balance" data-i18n-data-label="common.balance">
        {money(max(decimal(value(@invoice, "due_balance")), 0))}
      </td>
      <td
        class="table-cell invoice-salesperson"
        data-label="Sales Person"
        data-i18n-data-label="pos.customers.salesPerson"
        title={value(@invoice, "login") || ""}
      >
        {value(@invoice, "login") || "—"}
      </td>
      <td
        class="table-cell invoice-actions"
        data-label="Actions"
        data-i18n-data-label="common.actions"
      >
        <button
          :if={value(@invoice, "invoice_status") != "cancelled"}
          class="btn invoice-cancel"
          type="button"
          data-variant="ghost"
          data-size="sm"
          phx-click="open_cancel"
          phx-value-id={@id}
        >
          <span data-i18n="common.cancel">Cancel</span>
        </button>
        <span :if={value(@invoice, "invoice_status") == "cancelled"}>{value(@invoice, "cancelled_by") || "—"}</span>
      </td>
    </tr>
    """
  end

  attr :invoice, :map, required: true
  attr :detail, :any, required: true
  attr :methods, :map, required: true
  attr :amounts, :map, required: true

  defp invoice_detail(assigns) do
    id = integer(value(assigns.invoice, "id"))
    assigns = assign(assigns, :id, id)

    ~H"""
    <tr class="table-row invoice-details-row">
      <td class="table-cell" colspan="9">
        <section class="card invoice-details-card">
          <%= if @detail do %>
            <div
              class={["invoice-due-marker", invoice_due_marker_class(@detail)]}
              style={"width: #{invoice_due_marker_width(@detail)};"}
            >
            </div>
            <div class="card-header">
              <div class="invoice-detail-heading">
                <h3 class="card-title">{@detail.sequence || "Invoice ##{@detail.id}"}</h3>
                <p class="card-description">
                  <span data-i18n={
                    if @detail.client && @detail.client.name, do: nil, else: "invoice.walkIn"
                  }>
                    {(@detail.client && @detail.client.name) || "Walk-in customer"}
                  </span>
                  · {@detail.sale_type ||
                    "Sales"} · {@detail.login || "—"}
                </p>
                <p class="card-description invoice-due-date">
                  <span data-i18n="invoice.dueDate">Due date:</span> {invoice_due_date(
                    @detail.due_date
                  )}
                </p>
              </div>
              <div class="invoice-detail-print">
                <button
                  class="btn invoice-print-copy"
                  type="button"
                  data-variant="outline"
                  data-size="sm"
                  phx-click="reprint_invoice"
                  phx-value-id={@detail.id}
                >
                  <span data-i18n="invoice.printCopy">Print Copy</span>
                </button>
              </div>
              <div class="invoice-detail-actions">
                <.payment_form
                  :if={@detail.invoice_status == "open"}
                  detail={@detail}
                  methods={@methods}
                  amounts={@amounts}
                /><span
                  :if={@detail.invoice_status in ["close", "cancelled"]}
                  class={[
                    "invoice-status",
                    "invoice-detail-status",
                    "invoice-status-#{@detail.invoice_status}"
                  ]}
                >
                  <span data-i18n={status_label_key(@detail.invoice_status)}>
                    {status_label(@detail.invoice_status)}
                  </span>
                </span>
              </div>
            </div>
            <div class="card-content">
              <div class="table-container invoice-payment-history">
                <p class="invoice-table-section-title" data-i18n="invoice.payments">Payments</p>
                <table class="table">
                  <thead>
                    <tr class="table-row invoice-payment-columns">
                      <th class="table-head" data-i18n="common.payment">Payment</th>
                      <th class="table-head" data-i18n="common.date">Date</th>
                      <th class="table-head" data-i18n="common.user">User</th>
                      <th class="table-head" data-i18n="invoice.method">Method</th>
                      <th class="table-head" data-i18n="invoice.amount">Amount</th>
                      <th class="table-head" data-i18n="common.status">Status</th>
                      <th class="table-head">
                        <span class="sr-only" data-i18n="common.action">Action</span>
                      </th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :if={@detail.payments == []} class="table-row">
                      <td class="table-cell muted" colspan="7" data-i18n="invoice.noPayments">
                        No payments recorded.
                      </td>
                    </tr>
                    <tr :for={payment <- @detail.payments} class="table-row">
                      <td class="table-cell" data-i18n="common.payment">Payment</td>
                      <td class="table-cell">{date_only(payment.date_create)}</td>
                      <td class="table-cell">{payment.login || @detail.login || "—"}</td>
                      <td class="table-cell">
                        <span data-i18n={
                          if payment.type == "CC", do: "pos.checkout.creditCard", else: "common.cash"
                        }>
                          {if payment.type == "CC", do: "Credit Card", else: "Cash"}
                        </span>
                      </td>
                      <td class="table-cell numeric">{money(payment.amount)}</td>
                      <td class="table-cell">
                        <span data-i18n={
                          if @detail.invoice_status == "close",
                            do: "common.complete",
                            else: "invoice.partial"
                        }>
                          {if @detail.invoice_status == "close", do: "Complete", else: "Partial"}
                        </span>
                      </td>
                      <td class="table-cell">
                        <button
                          class="btn"
                          type="button"
                          data-variant="outline"
                          data-size="sm"
                          phx-click="print_payment"
                          phx-value-invoice_id={@detail.id}
                          phx-value-payment_id={payment.id}
                        >
                          <span data-i18n="invoice.printPayment">Print payment</span>
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div class="table-container">
                <p class="invoice-table-section-title" data-i18n="invoice.lineItems">Line items</p>
                <table class="table invoice-detail-lines">
                  <thead>
                    <tr class="table-row invoice-line-columns">
                      <th class="table-head" data-i18n="common.product">Product</th>
                      <th class="table-head" data-i18n="common.quantity">Quantity</th>
                      <th class="table-head" data-i18n="invoice.unitPrice">Unit price</th>
                      <th class="table-head" data-i18n="invoice.price">Price</th>
                      <th class="table-head" data-i18n="common.discount">Discount</th>
                      <th class="table-head" aria-hidden="true"></th>
                      <th class="table-head" data-i18n="common.total">Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={line <- @detail.lines} class="table-row">
                      <td class="table-cell">{(line.product && line.product.name) || "—"}</td>
                      <td class="table-cell numeric">{line.quantity}</td>
                      <td class="table-cell numeric">{money(line.amount)}</td>
                      <td class="table-cell numeric">{money(line.line_price)}</td>
                      <td class="table-cell numeric">
                        {discount_display(line.discount, line.discount_type, line.discount_input)}
                      </td>
                      <td class="table-cell" aria-hidden="true"></td>
                      <td class="table-cell numeric">{money(line.invoice_total)}</td>
                    </tr>
                  </tbody>
                  <tfoot>
                    <tr class="table-row invoice-line-summary">
                      <td class="table-cell" colspan="4" aria-hidden="true"></td>
                      <td class="table-cell numeric invoice-line-summary-discount">
                        {if decimal(@detail.discount) > 0, do: money(@detail.discount), else: "-"}
                      </td>
                      <th class="table-cell" data-i18n="common.subtotal">Subtotal</th>
                      <td class="table-cell numeric">{money(@detail.sub)}</td>
                    </tr>
                    <tr class="table-row invoice-line-summary">
                      <td class="table-cell" colspan="4" aria-hidden="true"></td>
                      <td class="table-cell numeric invoice-line-summary-discount">-</td>
                      <th class="table-cell" data-i18n="common.tax18">Tax (18%)</th>
                      <td class="table-cell numeric">{money(@detail.tax_amount)}</td>
                    </tr>
                    <tr
                      :if={decimal(@detail.delivery_charge) > 0}
                      class="table-row invoice-line-summary"
                    >
                      <td class="table-cell" colspan="4" aria-hidden="true"></td>
                      <td class="table-cell numeric invoice-line-summary-discount">-</td>
                      <th class="table-cell" data-i18n="pos.checkout.delivery">Delivery</th>
                      <td class="table-cell numeric">{money(@detail.delivery_charge)}</td>
                    </tr>
                    <tr class="table-row invoice-line-summary invoice-line-summary-total">
                      <td class="table-cell" colspan="4" aria-hidden="true"></td>
                      <td class="table-cell numeric invoice-line-summary-discount">-</td>
                      <th class="table-cell" data-i18n="common.total">Total</th>
                      <td class="table-cell numeric">{money(@detail.amount)}</td>
                    </tr>
                  </tfoot>
                </table>
              </div>
              <section
                :if={@detail.additional_info && String.trim(@detail.additional_info) != ""}
                class="invoice-memo"
              >
                <p class="invoice-memo-text">{@detail.additional_info}</p>
                <div class="invoice-memo-salesperson">
                  <span class="avatar invoice-memo-avatar">{String.first((@detail.salesperson && @detail.salesperson.name) || @detail.login || "?")}</span>{(@detail.salesperson &&
                                                                                                                                                               @detail.salesperson.name) ||
                    @detail.login || "—"}
                </div>
              </section>
            </div>
          <% end %>
        </section>
      </td>
    </tr>
    """
  end

  attr :detail, :map, required: true
  attr :methods, :map, required: true
  attr :amounts, :map, required: true

  defp payment_form(assigns) do
    ~H"""
    <form class="invoice-payment" phx-change="change_payment_amount" phx-submit="add_payment">
      <input type="hidden" name="_id" value={@detail.id} />
      <div class="invoice-payment-row">
        <div class="invoice-payment-amount">
          <label
            class="sr-only"
            for={"invoice-payment-#{@detail.id}"}
            data-i18n="invoice.paymentAmount"
          >
            Payment amount
          </label>
          <input
            id={"invoice-payment-#{@detail.id}"}
            class="input numeric"
            name="amount"
            value={Map.get(@amounts, @detail.id, "0")}
            type="number"
            inputmode="decimal"
            min="0.01"
            max={decimal(@detail.due_balance)}
            step="0.01"
            required
          />
        </div>
        <.method_buttons id={@detail.id} row="partial" methods={@methods} />
        <button
          class="btn"
          type="submit"
          name="row"
          value="partial"
          data-variant="outline"
          phx-disable-with="Apply"
        >
          <span data-i18n="common.apply">Apply</span>
        </button>
      </div>
      <div class="invoice-payment-row invoice-payment-payoff">
        <input
          class="input numeric"
          value={money_text(@detail.due_balance)}
          type="text"
          inputmode="decimal"
          readonly
        /><.method_buttons
          id={@detail.id}
          row="payoff"
          methods={@methods}
        />
        <button
          class="btn"
          type="submit"
          name="row"
          value="payoff"
          formnovalidate
          data-variant="default"
          phx-disable-with="Pay off"
        >
          <span data-i18n="invoice.payOff">Pay off</span>
        </button>
      </div>
    </form>
    """
  end

  attr :id, :integer, required: true
  attr :row, :string, required: true
  attr :methods, :map, required: true

  defp method_buttons(assigns) do
    selected = Map.get(assigns.methods, {assigns.id, assigns.row}, "CASH")
    assigns = assign(assigns, :selected, selected)

    ~H"""
    <div
      class="invoice-payment-methods sequence-options"
      role="group"
      aria-label="Payment method"
      data-i18n-aria-label="pos.checkout.paymentMethod"
    >
      <button
        :for={{type, label} <- [{"CASH", "Cash"}, {"CC", "Credit Card"}]}
        class="btn"
        type="button"
        data-variant={if @selected == type, do: "default", else: "secondary"}
        phx-click="select_payment_method"
        phx-value-id={@id}
        phx-value-row={@row}
        phx-value-type={type}
        aria-pressed={to_string(@selected == type)}
      >
        <span data-i18n={if type == "CC", do: "pos.checkout.creditCard", else: "common.cash"}>
          {label}
        </span>
      </button>
    </div>
    """
  end

  attr :month, :any, required: true
  attr :range, :map, required: true

  defp calendar_popover(assigns) do
    ~H"""
    <div
      id="invoice-date-range-dialog"
      class="invoice-date-popover"
      role="dialog"
      aria-modal="false"
      aria-labelledby="invoice-date-range-title"
    >
      <div class="dialog-content">
        <div class="dialog-header">
          <h2 id="invoice-date-range-title" class="dialog-title" data-i18n="invoice.selectDateRange">
            Select date range
          </h2>
          <p class="dialog-description">
            <span data-i18n={
              if @range.from != "" && @range.to == "",
                do: "invoice.chooseEndDate",
                else: "invoice.chooseStartEndDate"
            }>
              {if @range.from != "" && @range.to == "",
                do: "Choose an end date.",
                else: "Choose a start date, then an end date."}
            </span>
          </p>
        </div>
        <hr class="separator" />
        <div class="calendar-header">
          <button
            class="btn"
            type="button"
            data-variant="ghost"
            data-size="icon-sm"
            phx-click="calendar_month"
            phx-value-direction="previous"
            aria-label="Previous month"
            data-i18n-aria-label="invoice.previousMonth"
          >
            ‹
          </button>
          <h3 class="h4">{Calendar.strftime(@month, "%B %Y")}</h3>
          <button
            class="btn"
            type="button"
            data-variant="ghost"
            data-size="icon-sm"
            phx-click="calendar_month"
            phx-value-direction="next"
            aria-label="Next month"
            data-i18n-aria-label="invoice.nextMonth"
          >
            ›
          </button>
        </div>
        <div class="calendar-weekdays" aria-hidden="true">
          <span>Su</span><span>Mo</span><span>Tu</span><span>We</span><span>Th</span><span>Fr</span><span>Sa</span>
        </div>
        <div class="calendar-grid" role="grid">
          <span :for={_ <- calendar_blanks(@month)}></span><button
            :for={date <- Date.range(@month, month_end(@month))}
            class="btn calendar-day"
            data-range={calendar_day_class(date, @range)}
            type="button"
            data-variant="ghost"
            data-size="icon-sm"
            phx-click="select_date"
            phx-value-date={Date.to_iso8601(date)}
            aria-selected={to_string(Date.to_iso8601(date) in [@range.from, @range.to])}
          >{date.day}</button>
        </div>
        <div class="dialog-footer">
          <button class="btn" type="button" data-variant="ghost" phx-click="clear_range">
            <span data-i18n="common.clear">Clear</span>
          </button>
          <button class="btn" type="button" data-variant="outline" phx-click="close_calendar"><span data-i18n="common.cancel">Cancel</span></button><button
            class="btn"
            type="button"
            data-variant="default"
            phx-click="apply_range"
          ><span data-i18n="invoice.applyRange">Apply range</span></button>
        </div>
      </div>
    </div>
    """
  end

  attr :invoice, :any, required: true

  defp cancel_dialog(assigns),
    do: ~H"""
    <dialog
      id="invoice-cancel-dialog"
      class="dialog"
      data-size="sm"
      open
      role="dialog"
      aria-modal="true"
      aria-labelledby="invoice-cancel-title"
    >
      <div class="dialog-content">
        <div class="dialog-header">
          <h2 id="invoice-cancel-title" class="dialog-title" data-i18n="invoice.cancelInvoiceTitle">
            Cancel invoice?
          </h2>
          <p class="dialog-description" data-i18n="invoice.cancelInvoiceCopy">
            This restores the sold inventory. This action cannot be undone from the report.
          </p>
        </div>
        <div class="alert" data-variant="destructive" role="alert">
          <div class="alert-content">
            <h5 class="alert-title">{value(@invoice || %{}, "sequence") || "Selected invoice"}</h5>
            <p class="alert-description">
              <span data-i18n={
                if value(@invoice || %{}, "client_name"), do: nil, else: "invoice.walkIn"
              }>
                {value(@invoice || %{}, "client_name") || "Walk-in customer"}
              </span>
              · {money(value(@invoice || %{}, "amount"))} · {date_only(
                value(@invoice || %{}, "date_create")
              )}
            </p>
          </div>
        </div>
        <div class="dialog-footer">
          <button class="btn" type="button" data-variant="outline" phx-click="close_cancel">
            <span data-i18n="invoice.keepInvoice">Keep invoice</span>
          </button>
          <button
            class="btn"
            type="button"
            data-variant="destructive"
            phx-click="confirm_cancel"
          ><span data-i18n="invoice.cancelInvoice">Cancel invoice</span></button>
        </div>
      </div>
    </dialog>
    """

  defp headers,
    do: [
      {"Invoice", "sequence", "pos.customers.invoice"},
      {"Customer", "client_name", "pos.checkout.customer"},
      {"Date", "date_create", "common.date"},
      {"Due Date", "due_date", "invoice.dueDateHeader"},
      {"Status", "invoice_status", "common.status"},
      {"Total", "amount", "common.total"},
      {"Balance", "due_balance", "common.balance"},
      {"Sales Person", "login", "pos.customers.salesPerson"}
    ]

  defp calendar_blanks(month), do: List.duplicate(:blank, Date.day_of_week(month, :sunday) - 1)

  defp calendar_day_class(date, %{from: from, to: to}) do
    value = Date.to_iso8601(date)
    if from != "" and to != "" and value > from and value < to, do: "middle", else: nil
  end

  defp range_label("", _), do: "Any date"
  defp range_label(from, from), do: format_range_date(from)
  defp range_label(from, ""), do: format_range_date(from)
  defp range_label(from, to), do: "#{format_range_date(from)} – #{format_range_date(to)}"

  defp format_range_date(value),
    do: value |> Date.from_iso8601!() |> Calendar.strftime("%b %-d, %Y")

  defp discount_display(_discount, "percentage", input) when not is_nil(input), do: "#{input}%"
  defp discount_display(discount, _, _) when discount in [nil, 0, 0.0], do: "-"
  defp discount_display(discount, _, _), do: money(discount)
  defp print_request_id, do: "print-#{System.unique_integer([:positive])}"

  defp printable_detail(detail, socket),
    do:
      Map.put(
        detail,
        :store,
        socket.assigns.stores
        |> Enum.find(&(&1.id == detail.store_id))
        |> printable_store()
      )

  defp printable_store(nil), do: nil

  defp printable_store(store) do
    %{
      id: value(store, :id),
      name: value(store, :name),
      address: value(store, :address),
      company_id: value(store, :company_id),
      slogan: value(store, :slogan)
    }
  end

  defp print_prompt(:payment, sale, payment),
    do: %{
      title: "Print Payment",
      title_key: "invoice.printPaymentTitle",
      description: "Would you like to print this payment receipt?",
      description_key: "invoice.printPaymentPrompt",
      button: "Print payment",
      button_key: "invoice.printPayment",
      event: "printer:print-payment",
      payload: %{request_id: print_request_id(), sale: sale, payment: payment}
    }

  defp print_prompt(:invoice, invoice),
    do: %{
      title: "Print copy",
      title_key: "invoice.printCopyTitle",
      description: "Would you like to print the receipt?",
      description_key: "pos.print.prompt",
      button: "Print receipt",
      button_key: "pos.print.printReceipt",
      event: "printer:reprint-invoice",
      payload: %{request_id: print_request_id(), invoice: invoice}
    }

  defp update_print_prompt(%{assigns: %{print_prompt: nil}} = socket, _status, _printing),
    do: socket

  defp update_print_prompt(socket, status, printing),
    do: update(socket, :print_prompt, &Map.merge(&1, %{status: status, printing: printing}))

  attr :prompt, :map, required: true

  defp print_dialog(assigns) do
    ~H"""
    <dialog
      id="receipt-dialog"
      class="dialog"
      data-size="sm"
      open
      role="dialog"
      aria-modal="true"
      aria-labelledby="receipt-dialog-title"
    >
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
          <button
            id="skip-print"
            class="btn"
            type="button"
            data-variant="outline"
            phx-click="skip_print"
            disabled={@prompt[:printing] == true}
          >
            <span data-i18n="invoice.noReturnToPos">No, return to POS</span>
          </button>
          <button
            id="print-receipt"
            class="btn"
            type="button"
            data-variant="default"
            phx-click="confirm_print"
            disabled={@prompt[:printing] == true}
          ><span data-i18n={@prompt[:button_key]}>{@prompt.button}</span></button>
        </div>
      </div>
    </dialog>
    """
  end

  defp selected_store(stores, selected_id) do
    case Integer.parse(to_string(selected_id || "")) do
      {id, ""} -> Enum.find(stores, List.first(stores), &(&1.id == id))
      _ -> List.first(stores)
    end
  end
end
