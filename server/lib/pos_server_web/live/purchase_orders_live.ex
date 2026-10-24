defmodule TigooServerWeb.PurchaseOrdersLive do
  @moduledoc false
  use TigooServerWeb, :live_view

  import TigooServerWeb.PosLayoutComponents

  alias TigooServer.{Authentication, InventoryEvents, TenantContext}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.{InventoryContext, Orders, ProductCatalog}

  @sort_keys ~w(id from_origin_id to_store_id status last_updated user_requester)

  @impl true
  def mount(params, session, socket) do
    with token when is_binary(token) <- session["user_token"],
         {:ok, scope} <- Authentication.authenticate(token),
         true <- Scope.allowed?(scope, "pos.orders"),
         _ <- TenantContext.put_tenant(scope.tenant),
         {:ok, stores} <- InventoryContext.stores(scope),
         %{id: store_id} <- selected_store(stores, Map.get(params, "store_id") || session["store_id"]) do
      socket =
        socket
        |> assign(:page_title, gettext("Purchase Orders"))
        |> assign(:scope, scope)
        |> assign(:stores, stores)
        |> assign(:store_id, store_id)
        |> assign(:orders, [])
        |> assign(:sources, [])
        |> assign(:status_counts, %{})
        |> assign(:status_filter, "")
        |> assign(:sort, %{key: "last_updated", direction: :desc})
        |> assign(:view, :list)
        |> assign(:selected_order, nil)
        |> assign(:counting?, false)
        |> assign(:mode, :purchase)
        |> assign(:lines, [
          %{id: "line-1", product_id: nil, query: "", quantity: "", current_quantity: "—"}
        ])
        |> assign(:source_id, "")
        |> assign(:destination_id, to_string(store_id))
        |> assign(:product_dialog, nil)
        |> assign(:product_form_status, "")
        |> assign(:pricing_lists, ProductCatalog.pricing_lists(scope))
        |> assign(:status, "Loading purchase orders…")
        |> load_orders()

      if connected?(socket), do: InventoryEvents.subscribe(scope.tenant, store_id)
      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Order access is required.")
         |> redirect(to: ~p"/pos/login")}
    end
  end

  @impl true
  def handle_event("change_store", %{"store_id" => id}, socket) do
    with {store_id, ""} <- Integer.parse(id),
         true <- Enum.any?(socket.assigns.stores, &(&1.id == store_id)),
         {:ok, _} <- InventoryContext.authorize_store(socket.assigns.scope, store_id) do
      InventoryEvents.unsubscribe(socket.assigns.scope.tenant, socket.assigns.store_id)
      if connected?(socket), do: InventoryEvents.subscribe(socket.assigns.scope.tenant, store_id)
      {:noreply, socket |> assign(:store_id, store_id) |> reset_view() |> load_orders()}
    else
      _ -> {:noreply, put_flash(socket, :error, "The selected store is unavailable.")}
    end
  end

  def handle_event("sort", %{"key" => key}, socket) when key in @sort_keys do
    sort =
      if socket.assigns.sort.key == key,
        do: %{key: key, direction: flip(socket.assigns.sort.direction)},
        else: %{key: key, direction: :asc}

    {:noreply, socket |> assign(:sort, sort) |> update(:orders, &sort_orders(&1, sort))}
  end

  def handle_event("toggle_status", %{"status" => status}, socket) do
    filter = if socket.assigns.status_filter == status, do: "", else: status
    {:noreply, socket |> assign(:status_filter, filter) |> load_orders()}
  end

  def handle_event("reload_orders", _, socket), do: {:noreply, load_orders(socket)}

  def handle_event("show_order", %{"id" => id}, socket),
    do: {:noreply, show_order(socket, integer(id))}

  def handle_event("back_to_orders", _, socket),
    do: {:noreply, socket |> reset_view() |> load_orders()}

  def handle_event("navigate_order", %{"direction" => direction}, socket) do
    current = socket.assigns.selected_order && socket.assigns.selected_order.id
    index = Enum.find_index(socket.assigns.orders, &(&1.id == current)) || 0
    offset = if direction == "previous", do: -1, else: 1

    {:noreply,
     show_order(socket, socket.assigns.orders |> Enum.at(index + offset, %{}) |> value(:id))}
  end

  def handle_event("start_counting", _, socket),
    do:
      {:noreply,
       socket
       |> assign(:counting?, true)
       |> push_event("purchase-orders:focus-observed", %{index: 0})}

  def handle_event("observed_key", %{"index" => index, "key" => key}, socket)
      when key in ["Enter", "ArrowDown", "ArrowUp"] do
    delta = if key == "ArrowUp", do: -1, else: 1

    {:noreply,
     push_event(socket, "purchase-orders:focus-observed", %{index: max(0, integer(index) + delta)})}
  end

  def handle_event("observed_key", _params, socket), do: {:noreply, socket}

  def handle_event("receive_order", %{"observed" => observed}, socket) do
    lines =
      Enum.map(socket.assigns.selected_order.lines, fn line ->
        %{
          id: line.id,
          quantity_observed: integer(Map.get(observed, to_string(line.id), line.quantity))
        }
      end)

    case Orders.receive_order(socket.assigns.scope, socket.assigns.selected_order.id, %{
           lines: lines
         }) do
      {:ok, order} ->
        {:noreply,
         socket
         |> replace_order(order)
         |> assign(:selected_order, order)
         |> assign(:counting?, false)
         |> put_flash(:info, "Order processed.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Order could not be processed: #{reason_message(reason)}")}
    end
  end

  def handle_event("open_create", _, socket), do: {:noreply, open_form(socket, :purchase)}
  def handle_event("open_move", _, socket), do: {:noreply, open_form(socket, :move)}

  def handle_event("add_line", _, socket),
    do: {:noreply, update(socket, :lines, &(&1 ++ [blank_line(length(&1) + 1)]))}

  def handle_event("remove_line", %{"id" => id}, socket),
    do: {:noreply, update(socket, :lines, &Enum.reject(&1, fn line -> line.id == id end))}

  def handle_event("line_product", %{"id" => id, "product_id" => product_id}, socket) do
    {:noreply,
     update_line(socket, id, fn line ->
       Map.merge(line, %{
         product_id: integer(product_id),
         query: product_name(socket.assigns.products, product_id)
       })
     end)
     |> refresh_line_quantity(id)}
  end

  def handle_event("open_line_product", %{"line_id" => line_id}, socket),
    do:
      {:noreply,
       socket
       |> assign(:product_dialog, %{line_id: line_id, product: nil})
       |> assign(:product_form_status, "")}

  def handle_event(
        "edit_line_product",
        %{"line_id" => line_id, "product_id" => product_id},
        socket
      ) do
    case ProductCatalog.get(socket.assigns.scope, integer(product_id)) do
      {:ok, product} ->
        {:noreply,
         socket
         |> assign(:product_dialog, %{line_id: line_id, product: product})
         |> assign(:product_form_status, "")}

      _ ->
        {:noreply, put_flash(socket, :error, "Product could not be loaded.")}
    end
  end

  def handle_event("close_line_product", _, socket),
    do: {:noreply, socket |> assign(:product_dialog, nil) |> assign(:product_form_status, "")}

  def handle_event("save_line_product", params, socket) do
    dialog = socket.assigns.product_dialog
    attrs = product_attrs(params, socket)

    result =
      if dialog.product,
        do: ProductCatalog.update(socket.assigns.scope, dialog.product.id, attrs),
        else: ProductCatalog.create(socket.assigns.scope, attrs)

    case result do
      {:ok, product} ->
        socket = socket |> assign(:product_dialog, nil) |> load_orders()

        socket =
          if dialog.product,
            do: socket,
            else:
              socket
              |> update_line(
                dialog.line_id,
                &Map.merge(&1, %{product_id: product.id, query: product.name})
              )
              |> refresh_line_quantity(dialog.line_id)

        {:noreply,
         put_flash(
           socket,
           :info,
           if(dialog.product, do: "Product updated.", else: "Product created.")
         )}

      {:error, :default_price_required} ->
        {:noreply, assign(socket, :product_form_status, "A default selling price is required.")}

      {:error, :forbidden} ->
        {:noreply,
         assign(socket, :product_form_status, "You do not have permission to save products.")}

      {:error, _} ->
        {:noreply,
         assign(
           socket,
           :product_form_status,
           "Product could not be saved. Check the required fields."
         )}
    end
  end

  def handle_event("line_quantity", %{"quantity" => quantities}, socket)
      when is_map(quantities) do
    {id, quantity} = Enum.at(quantities, 0, {nil, nil})

    if is_binary(id),
      do: {:noreply, update_line(socket, id, &Map.put(&1, :quantity, quantity || ""))},
      else: {:noreply, socket}
  end

  def handle_event("line_quantity", _params, socket), do: {:noreply, socket}
  def handle_event("line_picker_key", _, socket), do: {:noreply, socket}

  def handle_event("change_source", %{"source_id" => id}, socket),
    do: {:noreply, socket |> assign(:source_id, id) |> refresh_all_line_quantities()}

  def handle_event("change_destination", %{"destination_id" => id}, socket),
    do: {:noreply, socket |> assign(:destination_id, id) |> refresh_all_line_quantities()}

  def handle_event("submit_order", _params, socket) do
    lines = valid_lines(socket.assigns.lines)

    cond do
      lines == [] ->
        {:noreply, put_flash(socket, :error, "Add a product with a requested quantity.")}

      socket.assigns.mode == :move and socket.assigns.source_id == socket.assigns.destination_id ->
        {:noreply,
         put_flash(socket, :error, "Origin Store and Destination Store must be different.")}

      socket.assigns.mode == :purchase ->
        create_purchase(socket, lines)

      true ->
        move_products(socket, lines)
    end
  end

  @impl true
  def handle_info({:inventory_changed, _}, socket) do
    socket = if socket.assigns.view == :detail, do: refresh_selected_order(socket), else: socket
    {:noreply, socket}
  end

  defp create_purchase(socket, lines) do
    attrs = %{
      order_type: "purchase",
      from_origin_id: integer(socket.assigns.source_id),
      to_store_id: integer(socket.assigns.destination_id),
      lines: lines
    }

    case Orders.create_order(socket.assigns.scope, attrs) do
      {:ok, order} ->
        {:noreply,
         socket
         |> update(:orders, &[order | &1])
         |> assign(:selected_order, order)
         |> assign(:view, :detail)
         |> put_flash(:info, "Purchase order created.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Order could not be created: #{reason_message(reason)}")}
    end
  end

  defp move_products(socket, lines) do
    attrs = %{
      from_origin_id: integer(socket.assigns.source_id),
      to_store_id: integer(socket.assigns.destination_id),
      lines: lines
    }

    case Orders.move_inventory(socket.assigns.scope, attrs) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reset_view()
         |> load_orders()
         |> put_flash(:info, "Products moved. Inventory was updated for both stores.")}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, "Products could not be moved: #{reason_message(reason)}")}
    end
  end

  defp load_orders(socket) do
    case {Orders.list_orders(
            socket.assigns.scope,
            socket.assigns.store_id,
            blank_to_nil(socket.assigns.status_filter)
          ), Orders.list_purchase_sources(socket.assigns.scope, socket.assigns.store_id),
          InventoryContext.list(socket.assigns.scope, socket.assigns.store_id, nil)} do
      {{:ok, %{entries: orders, status_counts: counts}}, {:ok, sources}, {:ok, inventory}} ->
        socket
        |> assign(:orders, sort_orders(orders, socket.assigns.sort))
        |> assign(:status_counts, counts)
        |> assign(:sources, sources)
        |> assign(
          :products,
          Enum.map(inventory, &%{id: &1.product_id, name: &1.product_name, code: &1.product_code})
        )
        |> assign(:status, order_status(orders))

      {{:ok, %{entries: orders, status_counts: counts}}, {:ok, sources}, _} ->
        socket
        |> assign(:orders, sort_orders(orders, socket.assigns.sort))
        |> assign(:status_counts, counts)
        |> assign(:sources, sources)
        |> assign(:products, [])
        |> assign(:status, order_status(orders))

      _ ->
        assign(socket, :status, "Purchase orders could not be loaded.")
    end
  end

  defp refresh_selected_order(socket) do
    case Orders.list_orders(socket.assigns.scope, socket.assigns.store_id, nil) do
      {:ok, %{entries: orders}} ->
        id = socket.assigns.selected_order.id

        socket
        |> assign(:orders, sort_orders(orders, socket.assigns.sort))
        |> assign(
          :selected_order,
          Enum.find(orders, socket.assigns.selected_order, &(&1.id == id))
        )

      _ ->
        socket
    end
  end

  defp show_order(socket, nil), do: socket

  defp show_order(socket, id),
    do:
      socket
      |> assign(:selected_order, Enum.find(socket.assigns.orders, &(&1.id == id)))
      |> assign(:view, :detail)
      |> assign(:counting?, false)

  defp reset_view(socket),
    do:
      socket |> assign(:view, :list) |> assign(:selected_order, nil) |> assign(:counting?, false)

  defp open_form(socket, mode),
    do:
      socket
      |> assign(:view, :form)
      |> assign(:mode, mode)
      |> assign(:source_id, if(mode == :move, do: to_string(socket.assigns.store_id), else: ""))
      |> assign(:destination_id, to_string(socket.assigns.store_id))
      |> assign(:lines, [blank_line(1)])

  defp replace_order(socket, order),
    do:
      update(socket, :orders, fn orders ->
        Enum.map(orders, fn current -> if current.id == order.id, do: order, else: current end)
        |> sort_orders(socket.assigns.sort)
      end)

  defp blank_line(number),
    do: %{
      id: "line-#{number}-#{System.unique_integer([:positive])}",
      product_id: nil,
      query: "",
      quantity: "",
      current_quantity: "—"
    }

  defp update_line(socket, id, fun),
    do:
      update(
        socket,
        :lines,
        &Enum.map(&1, fn line -> if line.id == id, do: fun.(line), else: line end)
      )

  defp refresh_all_line_quantities(socket),
    do:
      Enum.reduce(socket.assigns.lines, socket, fn line, acc ->
        refresh_line_quantity(acc, line.id)
      end)

  defp refresh_line_quantity(socket, id) do
    line = Enum.find(socket.assigns.lines, &(&1.id == id))

    store_id =
      integer(
        if socket.assigns.mode == :move,
          do: socket.assigns.source_id,
          else: socket.assigns.destination_id
      )

    quantity =
      if line && line.product_id && store_id > 0 do
        case InventoryContext.list(socket.assigns.scope, store_id, nil) do
          {:ok, entries} ->
            entries |> Enum.find(%{}, &(&1.product_id == line.product_id)) |> value(:quantity) ||
              0

          _ ->
            "—"
        end
      else
        "—"
      end

    update_line(socket, id, &Map.put(&1, :current_quantity, quantity))
  end

  defp valid_lines(lines),
    do:
      lines
      |> Enum.map(fn line -> %{product_id: line.product_id, quantity: integer(line.quantity)} end)
      |> Enum.filter(&(&1.product_id && &1.quantity > 0))

  defp product_attrs(params, socket) do
    prices =
      params
      |> Map.get("prices", %{})
      |> Enum.flat_map(fn {id, amount} ->
        case Float.parse(to_string(amount)) do
          {price, ""} when price >= 0 -> [%{pricing_id: integer(id), price: price}]
          _ -> []
        end
      end)

    %{
      store_id: socket.assigns.store_id,
      name: params |> Map.get("name", "") |> String.trim(),
      code: params |> Map.get("code", "") |> String.trim(),
      cost: decimal(Map.get(params, "cost")),
      image_raw: Map.get(params, "image_raw") || nil,
      prices: prices
    }
  end

  defp price_for(nil, _), do: nil

  defp price_for(product, pricing_id),
    do:
      Enum.find_value(product.prices || [], fn price ->
        if price.pricing_id == pricing_id, do: price.price
      end)

  defp image_source(nil), do: nil
  defp image_source("data:image/" <> _ = source), do: source
  defp image_source(source), do: "data:image/jpeg;base64,#{source}"

  defp sort_orders(orders, sort),
    do:
      Enum.sort_by(
        orders,
        &sort_value(&1, sort.key),
        if(sort.direction == :asc, do: :asc, else: :desc)
      )

  defp sort_value(order, key) when key in ["id"], do: value(order, String.to_atom(key)) || 0

  defp sort_value(order, key),
    do: value(order, String.to_atom(key)) |> to_string() |> String.downcase()

  defp flip(:asc), do: :desc
  defp flip(:desc), do: :asc
  defp integer(value) when is_integer(value), do: value

  defp integer(value) do
    case Integer.parse(to_string(value || "")) do
      {number, _} -> number
      :error -> 0
    end
  end

  defp value(nil, _), do: nil
  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
  defp order_status([]), do: "No purchase orders found."
  defp order_status(orders), do: "#{length(orders)} purchase orders"

  defp product_name(products, id),
    do:
      products
      |> Enum.find(%{}, fn product -> to_string(product.id) == to_string(id) end)
      |> value(:name) || ""

  defp reason_message(%Ecto.Changeset{}), do: "Check the required fields."
  defp reason_message(reason), do: to_string(reason)
  defp decimal(%Decimal{} = value), do: Decimal.to_float(value)
  defp decimal(value) when is_number(value), do: value * 1.0
  defp decimal(_), do: 0.0
  defp datetime(nil), do: "—"
  defp datetime(%NaiveDateTime{} = value), do: Calendar.strftime(value, "%d/%m/%Y %-I:%M %p")
  defp datetime(value), do: to_string(value)
  defp closed?(order), do: value(order, :status) in ["received", "closed"]

  defp requested_cost(line),
    do: decimal(value(line, :product_cost)) * (value(line, :quantity) || 0)

  defp line_cost(line, order),
    do:
      decimal(value(line, :product_cost)) *
        if(closed?(order),
          do: value(line, :quantity_observed) || value(line, :quantity) || 0,
          else: value(line, :quantity) || 0
        )

  defp difference(line, order),
    do: if(closed?(order), do: line_cost(line, order) - requested_cost(line), else: 0.0)

  defp order_cost(order),
    do: Enum.reduce(value(order, :lines) || [], 0.0, &(line_cost(&1, order) + &2))

  defp order_difference(order),
    do: Enum.reduce(value(order, :lines) || [], 0.0, &(difference(&1, order) + &2))

  defp discrepancy?(order),
    do:
      closed?(order) &&
        Enum.any?(value(order, :lines) || [], fn line ->
          (value(line, :quantity_observed) || value(line, :quantity)) != value(line, :quantity)
        end)

  defp sort_aria(sort, key) when sort.key == key,
    do: if(sort.direction == :asc, do: "ascending", else: "descending")

  defp sort_aria(_, _), do: "none"
  defp source_options(:move, stores, _sources), do: stores
  defp source_options(_, _stores, sources), do: sources
  defp purchase_order_header_key("Order ID"), do: "orders.orderId"
  defp purchase_order_header_key("Source"), do: "orders.source"
  defp purchase_order_header_key("Destination store"), do: "orders.destinationStore"
  defp purchase_order_header_key("Order cost"), do: "orders.orderCost"
  defp purchase_order_header_key("Cost difference"), do: "orders.costDifference"
  defp purchase_order_header_key("Status"), do: "common.status"
  defp purchase_order_header_key("Last updated"), do: "orders.lastUpdated"
  defp purchase_order_header_key("Created by"), do: "orders.createdBy"

  @impl true
  def render(assigns) do
    ~H"""
    <.pos_layout
      id="purchase-orders-live"
      class="pos-shell invoice-view"
      active_page={:orders}
      scope={@scope}
      stores={@stores}
      store_id={@store_id}
      phx-hook="PurchaseOrders"
    >
      <section class="catalog-panel" data-view="orders" aria-labelledby="orders-title">
        <section
          :if={@view == :list}
          id="orders-screen"
          class="operations-screen"
          aria-labelledby="orders-title"
        >
          <div class="operations-fixed">
            <header class="topbar operations-topbar">
              <div class="brand-lockup">
                <span class="brand-mark" aria-hidden="true">E</span>
                <div>
                  <p class="eyebrow" data-i18n="inventory.operations">Operations</p>
                  <h2 id="orders-title" tabindex="-1">
                    <span data-i18n="orders.purchaseOrders">Purchase Orders</span> — {active_store(@stores, @store_id)}
                  </h2>
                </div>
              </div>
              <div class="form-actions">
                <button class="btn" type="button" data-variant="default" phx-click="open_create">
                  <span data-i18n="orders.createPurchaseOrder">Create purchase order</span>
                </button><button
                  class="btn"
                  type="button"
                  data-variant="default"
                  phx-click="open_move"
                ><span data-i18n="orders.moveProducts">Move Product</span></button>
              </div>
            </header>
            <p class="operations-status" role="status">{@status}</p>
          </div>
          <section class="inventory-summary-section" aria-label="Purchase order status KPIs">
            <section class="inventory-summary" aria-live="polite">
              <article :for={{status, count} <- @status_counts} class="card inventory-summary-card">
                <button
                  class="btn inventory-kpi"
                  type="button"
                  data-variant={if @status_filter == status, do: "secondary", else: "ghost"}
                  aria-pressed={to_string(@status_filter == status)}
                  phx-click="toggle_status"
                  phx-value-status={status}
                >
                  <div class="card-header">
                    <p class="card-title">{status}</p>
                  </div>
                  <div class="card-content">
                    <p class="inventory-kpi-value numeric">{count}</p>
                    <p class="inventory-kpi-detail" data-i18n="orders.purchaseOrders">Purchase orders</p>
                  </div>
                </button>
              </article>
            </section>
          </section>
          <div class="table-container operations-table-container">
            <table class="table operations-table">
              <caption class="table-caption" data-i18n="orders.currentStore">Purchase orders for the current store.</caption>
              <thead>
                <tr class="table-row">
                  <%= for {label, key} <- [{"Order ID", "id"}, {"Source", "from_origin_id"}, {"Destination store", "to_store_id"}, {"Order cost", nil}, {"Cost difference", nil}, {"Status", "status"}, {"Last updated", "last_updated"}, {"Created by", "user_requester"}] do %>
                    <th
                      class="table-head"
                      scope="col"
                      aria-sort={if key, do: sort_aria(@sort, key), else: "none"}
                    >
                      <button
                        :if={key}
                        class="btn operations-sort"
                        type="button"
                        data-variant="ghost"
                        phx-click="sort"
                        phx-value-key={key}
                      >
                          <span data-i18n={purchase_order_header_key(label)}>{label}</span>
                      </button><span :if={!key} data-i18n={purchase_order_header_key(label)}>{label}</span>
                    </th>
                  <% end %>
                  <th class="table-head"><span class="sr-only" data-i18n="common.action">Action</span></th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={order <- @orders}
                  class={[
                    "table-row purchase-order-row",
                    if(closed?(order), do: "purchase-order-received", else: "purchase-order-open")
                  ]}
                >
                  <td class="table-cell" data-label="Purchase order" data-i18n-data-label="orders.purchaseOrder">#{order.id}</td>
                  <td class="table-cell" data-label="Source" data-i18n-data-label="orders.source">{order.from_origin_name || "—"}</td>
                  <td class="table-cell" data-label="Destination store" data-i18n-data-label="orders.destinationStore">
                    {order.to_store_name || "—"}
                  </td>
                  <td class="table-cell numeric" data-label="Order cost" data-i18n-data-label="orders.orderCost">
                    {money(order_cost(order))}
                  </td>
                  <td class="table-cell numeric" data-label="Cost difference" data-i18n-data-label="orders.costDifference">
                    {money(order_difference(order))}
                  </td>
                  <td class="table-cell" data-label="Status" data-i18n-data-label="common.status">
                    <span data-i18n={if closed?(order), do: "common.closed", else: "common.open"}>{if closed?(order), do: "Closed", else: "Open"}</span><span
                      :if={discrepancy?(order)}
                      class="counting-warning"
                      role="img"
                      aria-label="Observed quantities differ from requested quantities"
                      title="Observed quantities differ from requested quantities"
                    > ⚠</span>
                  </td>
                  <td class="table-cell" data-label="Last updated" data-i18n-data-label="orders.lastUpdated">
                    {datetime(order.date_closed || order.date_opened)}
                  </td>
                  <td class="table-cell" data-label="Created by" data-i18n-data-label="orders.createdBy">{order.user_requester || "—"}</td>
                  <td class="table-cell" data-label="Actions" data-i18n-data-label="common.actions">
                    <button
                      class="btn"
                      type="button"
                      data-variant="outline"
                      data-size="sm"
                      phx-click="show_order"
                      phx-value-id={order.id}
                    >
                      <span data-i18n="common.view">View</span>
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
        <section
          :if={@view in [:detail, :form]}
          id="purchase-order-screen"
          class="operations-screen purchase-order-screen"
          aria-labelledby="purchase-order-title"
        >
          <div class="operations-fixed">
            <header class="topbar operations-topbar">
              <div class="brand-lockup">
                <span class="brand-mark" aria-hidden="true">E</span>
                <div>
                  <p class="eyebrow" data-i18n="inventory.operations">Operations</p>
                  <h2 id="purchase-order-title" tabindex="-1">
                    {if @view == :form and @mode == :move, do: "Move products", else: "Purchase order"} — {active_store(
                      @stores,
                      @store_id
                    )}
                  </h2>
                </div>
              </div>
              <button
                class="btn"
                type="button"
                data-variant="outline"
                data-size="sm"
                phx-click="back_to_orders"
              >
                <span data-i18n="orders.backToOrders">Back to orders</span>
              </button>
            </header>
          </div>
          <article :if={@view == :detail} class="card purchase-order-detail">
            <div class="card-header">
              <div>
                <p class="eyebrow">Order #{@selected_order.id}</p>
                <h3 class="card-title">
                  <span data-i18n={if closed?(@selected_order), do: "common.closed", else: "common.open"}>{if closed?(@selected_order), do: "Closed", else: "Open"}</span><span
                    :if={discrepancy?(@selected_order)}
                    class="counting-warning"
                  > ⚠</span>
                </h3>
                <p class="field-description">
                  {@selected_order.from_origin_name || "External source"} → {@selected_order.to_store_name ||
                    "—"} · Created by {@selected_order.user_requester || "—"} · {datetime(
                    @selected_order.date_opened
                  )}
                </p>
              </div>
              <div class="purchase-order-actions">
                <button
                  class="btn"
                  type="button"
                  data-variant="outline"
                  data-size="sm"
                  phx-click="navigate_order"
                  phx-value-direction="previous"
                  disabled={order_position(@orders, @selected_order.id) <= 0}
                >
                  <span data-i18n="orders.previous">Previous</span>
                </button><button
                  class="btn"
                  type="button"
                  data-variant="outline"
                  data-size="sm"
                  phx-click="navigate_order"
                  phx-value-direction="next"
                  disabled={order_position(@orders, @selected_order.id) >= length(@orders) - 1}
                ><span data-i18n="orders.next">Next</span></button><button
                  :if={!closed?(@selected_order) and !@counting?}
                  class="btn"
                  type="button"
                  data-variant="default"
                  phx-click="start_counting"
                ><span data-i18n="orders.startCounting">Start Counting</span></button><button
                  :if={!closed?(@selected_order) and @counting?}
                  class="btn"
                  type="submit"
                  form="receive-order-form"
                  data-variant="default"
                ><span data-i18n="orders.processOrder">Process Order</span></button>
              </div>
            </div>
            <form id="receive-order-form" class="card-content" phx-submit="receive_order">
              <div class="table-container purchase-order-lines-scroll">
                <table class="table purchase-order-lines-table">
                  <caption class="table-caption" data-i18n="orders.productsInOrder">Products in this purchase order.</caption>
                  <thead>
                    <tr class="table-row">
                      <th class="table-head" data-i18n="common.product">Product</th>
                      <th class="table-head" data-i18n="pos.catalog.sku">SKU</th>
                      <th class="table-head" data-i18n="inventory.currentQuantity">Current quantity</th>
                      <th class="table-head" data-i18n="orders.requested">Requested</th>
                      <th class="table-head" data-i18n="orders.observed">Observed</th>
                      <th class="table-head" data-i18n="orders.itemCost">Item cost</th>
                      <th class="table-head" data-i18n="orders.costDifference">Cost difference</th>
                      <th class="table-head" data-i18n="common.status">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={{line, index} <- Enum.with_index(@selected_order.lines)}
                      class="table-row"
                    >
                      <td class="table-cell">{line.product_name}</td>
                      <td class="table-cell">{line.product_code || "—"}</td>
                      <td class="table-cell numeric">{line.current_quantity || 0}</td>
                      <td class="table-cell numeric">{line.quantity}</td>
                      <td class="table-cell observed-cell">
                        <input
                          class="input numeric observed-input"
                          type="number"
                          inputmode="numeric"
                          min="0"
                          name={"observed[#{line.id}]"}
                          value={line.quantity_observed || line.quantity}
                          disabled={!@counting?}
                          phx-keydown="observed_key"
                          phx-value-index={index}
                        />
                      </td>
                      <td class="table-cell numeric">{money(line_cost(line, @selected_order))}</td>
                      <td class="table-cell numeric">{money(difference(line, @selected_order))}</td>
                      <td class="table-cell">{line.status}</td>
                    </tr>
                  </tbody>
                  <tfoot>
                    <tr class="purchase-order-total-row">
                      <td colspan="5"></td>
                      <td class="numeric purchase-order-total-amount">
                        {money(order_cost(@selected_order))}
                      </td>
                      <td class="numeric purchase-order-difference-amount">
                        {money(order_difference(@selected_order))}
                      </td>
                      <td></td>
                    </tr>
                  </tfoot>
                </table>
              </div>
            </form>
          </article>
          <article :if={@view == :form} class="card purchase-order-detail">
            <div class="card-header">
              <div>
                <p class="eyebrow" data-i18n="inventory.operations">Operations</p>
                <h3 class="card-title">
                  <span data-i18n={if @mode == :move, do: "orders.moveProducts", else: "orders.createPurchaseOrder"}>{if @mode == :move, do: "Move products", else: "Create purchase order"}</span>
                </h3>
                <p class="field-description">
                  <span data-i18n={if @mode == :move, do: "orders.moveProductsCopy", else: "orders.addProductsCopy"}>{if @mode == :move,
                    do: "Move products from an origin store to a destination store.",
                    else: "Add products and confirm the requested quantities."}</span>
                </p>
              </div>
            </div>
            <form class="form card-content" phx-submit="submit_order">
              <div class="order-form-grid">
                <div class="form-field">
                  <label class="label" for="purchase-order-source">
                    <span data-i18n={if @mode == :move, do: "orders.originStore", else: "orders.sourceProvider"}>{if @mode == :move, do: "Origin store", else: "Source / provider"}</span>
                  </label><select
                    id="purchase-order-source"
                    class="select"
                    name="source_id"
                    phx-change="change_source"
                    required
                  ><option value="" selected={@source_id == ""} disabled data-i18n="orders.selectSource">Select a source</option><option
                    :for={source <- source_options(@mode, @stores, @sources)}
                    value={source.id}
                    selected={to_string(source.id) == @source_id}
                  >{source.name}</option></select>
                </div>
                <div class="form-field">
                  <label class="label" for="purchase-order-destination" data-i18n="orders.destinationStore">Destination store</label><select
                    id="purchase-order-destination"
                    class="select"
                    name="destination_id"
                    phx-change="change_destination"
                    required
                  ><option
                    :for={store <- @stores}
                    value={store.id}
                    selected={to_string(store.id) == @destination_id}
                  >{store.name}</option></select>
                </div>
              </div>
              <div id="order-lines" class="order-lines" phx-hook="PurchaseOrderLines">
                <div
                  :for={line <- @lines}
                  id={line.id}
                  class="order-line"
                  data-order-line
                  data-line-id={line.id}
                >
                  <button
                    class="btn"
                    type="button"
                    data-variant="outline"
                    data-size="icon-sm"
                    disabled={is_nil(line.product_id)}
                    aria-label="Edit selected product"
                    phx-click="edit_line_product"
                    phx-value-line_id={line.id}
                    phx-value-product_id={line.product_id}
                  >
                    ✎
                  </button>
                  <div class="product-combobox">
                    <input
                      class="input"
                      type="text"
                      value={line.query}
                      placeholder="Search products"
                      data-i18n-placeholder="inventory.searchProduct"
                      autocomplete="off"
                      spellcheck="false"
                      autocorrect="off"
                      autocapitalize="off"
                      role="combobox"
                      aria-label="Product"
                      data-i18n-aria-label="common.product"
                      aria-autocomplete="list"
                      aria-expanded="false"
                      aria-controls={"#{line.id}-products"}
                      phx-keydown="line_picker_key"
                      phx-key="Enter"
                    /><button
                      class="btn"
                      type="button"
                      data-variant="outline"
                      data-size="icon-sm"
                      aria-label="Create product"
                      data-i18n-aria-label="inventory.createProduct"
                      phx-click="open_line_product"
                      phx-value-line_id={line.id}
                    >
                      +
                    </button>
                    <ul id={"#{line.id}-products"} class="product-combobox-list" role="listbox" hidden>
                      <li :for={product <- @products} id={"#{line.id}-product-#{product.id}"}>
                        <button
                          class="btn"
                          type="button"
                          role="option"
                          data-variant="ghost"
                          data-product-id={product.id}
                          data-product-name={product.name}
                          data-product-code={product.code || ""}
                        >
                          {product.name}{if product.code, do: " · #{product.code}", else: ""}
                        </button>
                      </li>
                    </ul>
                  </div>
                  <input
                    class="input numeric"
                    type="text"
                    value={line.current_quantity}
                    readonly
                    aria-label="Current inventory quantity"
                    data-i18n-aria-label="inventory.currentQuantity"
                  /><input
                    class="input"
                    type="number"
                    inputmode="numeric"
                    min="1"
                    name={"quantity[#{line.id}]"}
                    value={line.quantity}
                    aria-label="Requested quantity"
                    data-i18n-aria-label="orders.requested"
                    phx-change="line_quantity"
                  /><button
                    class="btn"
                    type="button"
                    data-variant="ghost"
                    data-size="sm"
                    phx-click="remove_line"
                    phx-value-id={line.id}
                  >
                    Remove
                  </button>
                </div>
              </div>
              <button
                class="btn"
                type="button"
                data-variant="outline"
                data-size="sm"
                phx-click="add_line"
              >
                Add product
              </button>
              <div class="form-actions">
                <button class="btn" type="submit" data-variant="default">
                  {if @mode == :move, do: "Move products", else: "Create order"}
                </button>
              </div>
            </form>
          </article>
        </section>
      </section>
      <dialog
        :if={@product_dialog}
        id="product-dialog"
        class="dialog"
        data-size="lg"
        role="dialog"
        aria-modal="true"
        aria-labelledby="product-dialog-title"
      >
        <div class="dialog-content">
          <div class="dialog-header">
            <h2 id="product-dialog-title" class="dialog-title">
              {if @product_dialog.product, do: "Edit product", else: "Create product"}
            </h2>
            <p class="dialog-description">
              Catalog details and pricing-list values are saved as separate records.
            </p>
          </div>
          <form id="product-form" class="form dialog-body" phx-submit="save_line_product">
            <div class="form-field">
              <label class="label" for="product-name">
                Name <span class="text-destructive">*</span>
              </label>
              <input
                id="product-name"
                name="name"
                class="input"
                value={@product_dialog.product && @product_dialog.product.name}
                required
                autofocus
              />
            </div>
            <div class="product-form-row">
              <div class="form-field">
                <label class="label" for="product-cost">Cost</label>
                <input
                  id="product-cost"
                  name="cost"
                  class="input"
                  type="number"
                  inputmode="decimal"
                  min="0"
                  step="0.01"
                  value={(@product_dialog.product && @product_dialog.product.cost) || 0}
                />
              </div>
              <fieldset class="form-fieldset product-prices-fieldset">
                <legend>Price lists</legend>
                <div class="form-group">
                  <div :for={list <- @pricing_lists} class="product-price-row">
                    <label class="label" for={"product-price-#{list.id}"}>{list.label}</label>
                    <input
                      id={"product-price-#{list.id}"}
                      name={"prices[#{list.id}]"}
                      class="input"
                      type="number"
                      inputmode="decimal"
                      min="0"
                      step="0.01"
                      placeholder="Price"
                      value={price_for(@product_dialog.product, list.id)}
                      required={list.id == 1}
                    />
                  </div>
                </div>
              </fieldset>
            </div>
            <div class="form-field">
              <label class="label" for="product-code">SKU</label>
              <input
                id="product-code"
                name="code"
                class="input"
                value={@product_dialog.product && @product_dialog.product.code}
              />
            </div>
            <div
              id="product-image-dropzone"
              class="product-image-dropzone"
              tabindex="0"
              role="button"
              aria-describedby="product-image-help"
            >
              <img
                id="product-image-preview"
                class="product-image-preview"
                src={image_source(@product_dialog.product && @product_dialog.product.image_raw)}
                alt="Product preview"
                hidden={is_nil(@product_dialog.product && @product_dialog.product.image_raw)}
              /><label class="label" for="product-image">Image upload</label>
              <p id="product-image-help" class="field-description">
                Drop an image here or choose a file (max 10 MB). It will be resized and stored as Base64.
              </p>
              <input id="product-image" class="input" type="file" accept="image/*" /><input
                id="product-image-raw"
                name="image_raw"
                type="hidden"
                value={@product_dialog.product && @product_dialog.product.image_raw}
              />
            </div>
            <p class="field-description" role="status">{@product_form_status}</p>
            <div class="dialog-footer">
              <button class="btn" type="button" data-variant="outline" phx-click="close_line_product">
                Cancel
              </button><button class="btn" type="submit" data-variant="default">Save</button>
            </div>
          </form>
        </div>
      </dialog>
    </.pos_layout>
    """
  end

  defp active_store(stores, id),
    do: Enum.find_value(stores, "", fn store -> if store.id == id, do: store.name end)

  defp order_position(orders, id), do: Enum.find_index(orders, &(&1.id == id)) || 0

  defp selected_store(stores, selected_id) do
    case Integer.parse(to_string(selected_id || "")) do
      {id, ""} -> Enum.find(stores, List.first(stores), &(&1.id == id))
      _ -> List.first(stores)
    end
  end
end
