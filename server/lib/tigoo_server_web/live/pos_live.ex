defmodule TigooServerWeb.PosLive do
  use TigooServerWeb, :live_view

  import Ecto.Query, only: [from: 2]
  import TigooServerWeb.CustomerComponents
  import TigooServerWeb.PosLayoutComponents

  alias TigooServer.{Authentication, InventoryEvents, Repo, TenantContext}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.{Client, InventoryContext, Product, Sales, Sequence, Sql}

  @impl true
  def mount(params, session, socket) do
    with token when is_binary(token) <- session["user_token"],
         {:ok, scope} <- Authentication.authenticate(token),
         _tenant <- TenantContext.put_tenant(scope.tenant),
         {:ok, stores} <- InventoryContext.stores(scope) do
      store = selected_store(stores, Map.get(params, "store_id") || session["store_id"])

      socket =
        socket
        |> assign(:page_title, gettext("Point of Sale"))
        |> assign(:print_relay_token, token)
        |> assign(:scope, scope)
        |> assign(:stores, stores)
        |> assign(:store_id, store && store.id)
        |> assign(:products, [])
        |> assign(:cursor, nil)
        |> assign(:has_more, true)
        |> assign(:loading_products, false)
        |> assign(:product_search, "")
        |> assign(:catalog_view, initial_catalog_view(socket))
        |> assign(:cart, [])
        |> assign(:selected_customer, nil)
        |> assign(:customers, [])
        |> assign(:customer_search, "")
        |> assign(:customer_purchases, [])
        |> assign(:customer_dialog?, false)
        |> assign(:customer_form_status, "")
        |> assign(:saving_customer?, false)
        |> assign(:expanded_purchases, MapSet.new())
        |> assign(:checkout_stage, nil)
        |> assign(:dialog, nil)
        |> assign(:discount_target, nil)
        |> assign(:discount_type, "amount")
        |> assign(:discount_input, "0")
        |> assign(:order_discount, 0.0)
        |> assign(:order_discount_type, "amount")
        |> assign(:order_discount_mode, "amount")
        |> assign(:delivery, 0.0)
        |> assign(:delivery_open, false)
        |> assign(:delivery_custom_input, "")
        |> assign(:delivery_custom_selected, false)
        |> assign(:credit, false)
        |> assign(:credit_due_date, "")
        |> assign(:payments, [])
        |> assign(:sequence, "CF")
        |> assign(:sequences, sequence_options(scope.tenant))
        |> assign(:memo, "")
        |> assign(:print_prompt, nil)
        |> assign(:client_info, nil)
        |> assign(:mobile_cart_open, false)
        |> load_products()
        |> sync()

      if connected?(socket) and store, do: InventoryEvents.subscribe(scope.tenant, store.id)
      {:ok, socket}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, "Sign in is required to use POS.")
         |> redirect(to: ~p"/pos/login")}
    end
  end

  @impl true
  def handle_event("search_products", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :product_search, value)}

  def handle_event("clear_product_search", _, socket),
    do: {:noreply, assign(socket, :product_search, "")}

  def handle_event("load_more_products", _, socket), do: {:noreply, load_products(socket)}

  def handle_event("set_catalog_view", %{"view" => view}, socket) when view in ["cards", "table"],
    do: {:noreply, assign(socket, :catalog_view, view)}

  def handle_event("set_catalog_view", _, socket), do: {:noreply, socket}

  def handle_event("change_store", %{"store_id" => id}, socket) do
    with {store_id, ""} <- Integer.parse(id),
         true <- Enum.any?(socket.assigns.stores, &(&1.id == store_id)),
         {:ok, _} <- InventoryContext.authorize_store(socket.assigns.scope, store_id) do
      InventoryEvents.unsubscribe(socket.assigns.scope.tenant, socket.assigns.store_id)
      InventoryEvents.subscribe(socket.assigns.scope.tenant, store_id)

      socket =
        socket
        |> assign(:store_id, store_id)
        |> assign(:products, [])
        |> assign(:cursor, nil)
        |> assign(:has_more, true)
        |> assign(:cart, [])
        |> assign(:selected_customer, nil)
        |> sync()

      {:noreply, load_products(socket)}
    else
      _ -> {:noreply, put_flash(socket, :error, "The selected store is unavailable.")}
    end
  end

  def handle_event("add_product", _params, %{assigns: %{checkout_stage: stage}} = socket)
      when not is_nil(stage),
      do: {:noreply, socket}

  def handle_event("add_product", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.products, &(to_string(&1.id) == id)) do
      nil ->
        {:noreply, socket}

      product ->
        product = product_with_image(product, socket.assigns.store_id)

        {:noreply,
         socket |> add_product(product) |> sync() |> push_event("pos:cart-bump", %{id: id})}
    end
  end

  def handle_event(event, _params, %{assigns: %{checkout_stage: stage}} = socket)
      when event in ["increase_quantity", "decrease_quantity", "set_quantity", "remove_line"] and
             not is_nil(stage),
      do: {:noreply, socket}

  def handle_event("increase_quantity", %{"id" => id}, socket),
    do: {:noreply, change_quantity(socket, id, 1)}

  def handle_event("decrease_quantity", %{"id" => id}, socket),
    do: {:noreply, change_quantity(socket, id, -1)}

  def handle_event("set_quantity", %{"id" => id, "value" => value}, socket) do
    quantity =
      case Integer.parse(value) do
        {number, _} -> number
        :error -> 0
      end

    {:noreply, set_quantity(socket, id, quantity)}
  end

  def handle_event("remove_line", %{"id" => id}, socket),
    do:
      {:noreply,
       socket
       |> assign(:cart, Enum.reject(socket.assigns.cart, &(to_string(&1.id) == id)))
       |> sync()}

  def handle_event("clear_sale_prompt", _, socket),
    do: {:noreply, assign(socket, :dialog, :clear_sale)}

  def handle_event("clear_sale", _, socket),
    do:
      {:noreply,
       socket
       |> assign(:cart, [])
       |> assign(:order_discount, 0.0)
      |> assign(:order_discount_mode, "amount")
      |> assign(:delivery, 0.0)
      |> assign(:delivery_open, false)
      |> assign(:delivery_custom_input, "")
      |> assign(:delivery_custom_selected, false)
      |> assign(:credit, false)
      |> assign(:credit_due_date, "")
      |> assign(:payments, [])
      |> assign(:sequence, "CF")
      |> assign(:memo, "")
      |> assign(:dialog, nil)
       |> sync()}

  def handle_event("close_dialog", _, socket), do: {:noreply, assign(socket, :dialog, nil)}

  def handle_event(
        "open_line_discount",
        _params,
        %{assigns: %{checkout_stage: :payment}} = socket
      ),
      do: {:noreply, socket}

  def handle_event("open_line_discount", %{"id" => id}, socket) do
    cond do
      socket.assigns.order_discount > 0 ->
        {:noreply,
         put_flash(
           socket,
           :info,
           "An order discount is active. Remove it before applying an item discount."
         )}

      line = Enum.find(socket.assigns.cart, &(to_string(&1.id) == id)) ->
        discount_mode = Map.get(line, :discount_mode, line.discount_type)

        {:noreply,
         socket
         |> assign(:dialog, :discount)
         |> assign(:discount_target, id)
         |> assign(:discount_type, discount_mode)
         |> assign(:discount_input, discount_input_value(line.discount, discount_mode, line_gross(line)))}

      true ->
        {:noreply, socket}
    end
  end

  def handle_event("open_order_discount", _, %{assigns: %{checkout_stage: :payment}} = socket),
    do: {:noreply, socket}

  def handle_event("open_order_discount", _, socket) do
    if socket.assigns.cart == [] do
      {:noreply, socket}
    else
      discount_mode = Map.get(socket.assigns, :order_discount_mode, socket.assigns.order_discount_type)
      base = before_order_discount(socket)

      {:noreply,
       socket
       |> assign(:dialog, :discount)
       |> assign(:discount_target, nil)
       |> assign(:discount_type, discount_mode)
       |> assign(:discount_input, discount_input_value(socket.assigns.order_discount, discount_mode, base))}
    end
  end

  def handle_event("open_order_discount_key", %{"key" => key}, socket) when key in ["Enter", " "],
    do: handle_event("open_order_discount", %{}, socket)

  def handle_event("open_order_discount_key", _, socket), do: {:noreply, socket}

  def handle_event("set_discount_type", %{"type" => type}, socket)
      when type in ["amount", "percent", "final_price"],
      do: {:noreply, assign(socket, :discount_type, type)}

  def handle_event("change_discount", %{"value" => value}, socket),
    do: {:noreply, assign(socket, :discount_input, value)}

  def handle_event("clear_discount_input", _, socket),
    do: {:noreply, assign(socket, :discount_input, "")}

  def handle_event("clear_pos_flash", _, socket), do: {:noreply, clear_flash(socket, :info)}

  def handle_event("apply_discount", params, socket) do
    discount_type = Map.get(params, "discount_type", socket.assigns.discount_type)
    socket = assign(socket, :discount_type, discount_type)
    raw_value = Map.get(params, "value", socket.assigns.discount_input)
    value = float(raw_value)
    base = discount_base(socket.assigns)

    valid? =
      discount_type in ["amount", "percent", "final_price"] and value >= 0 and
        (discount_type != "percent" or value <= 100) and
        (discount_type != "final_price" or value <= base)

    if not valid?,
      do: {:noreply, put_flash(socket, :error, "Enter a valid discount.")},
      else: {:noreply, apply_discount(socket, discount_value(discount_type, raw_value, value, base))}
  end

  def handle_event("open_customer_picker", _, socket),
    do:
      {:noreply,
       socket
       |> assign(:dialog, :customer_picker)
       |> assign(:mobile_cart_open, false)
       |> load_customers()}

  def handle_event("search_customers", %{"value" => value}, socket),
    do: {:noreply, socket |> assign(:customer_search, value) |> load_customers()}

  def handle_event("select_customer", %{"id" => id}, socket),
    do:
      {:noreply,
       socket
       |> assign(
         :selected_customer,
         Enum.find(socket.assigns.customers, &(to_string(&1.id) == id))
       )
       |> assign(:dialog, nil)
       |> assign(:checkout_stage, nil)
       |> sync()}

  def handle_event("clear_customer", _, %{assigns: %{checkout_stage: stage}} = socket)
      when not is_nil(stage),
      do: {:noreply, socket}

  def handle_event("clear_customer", _, socket),
    do: {:noreply, socket |> assign(:selected_customer, nil) |> sync()}

  def handle_event("open_customer_dialog", _, socket),
    do: {:noreply, socket |> assign(:customer_dialog?, true) |> assign(:customer_form_status, "")}

  def handle_event("close_customer_dialog", _, socket),
    do:
      {:noreply,
       socket
       |> assign(:customer_dialog?, false)
       |> assign(:customer_form_status, "")
       |> assign(:saving_customer?, false)}

  def handle_event("create_customer", params, socket) do
    attrs =
      params
      |> Map.put("wholesaler", wholesaler_value(params["is_wholesaler"]))
      |> Map.delete("is_wholesaler")

    case %Client{} |> Client.changeset(attrs) |> Repo.insert(prefix: TenantContext.tenant!()) do
      {:ok, customer} ->
        customer = normalize_customer(customer)

        {:noreply,
         socket
         |> assign(:customer_dialog?, false)
         |> assign(:customer_form_status, "")
         |> assign(:saving_customer?, false)
         |> assign(:selected_customer, customer)
         |> assign(:dialog, nil)
         |> load_customers()
         |> sync()}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(
           :customer_form_status,
           "Could not create customer. Check the data and try again."
         )
         |> assign(:saving_customer?, false)}
    end
  end

  def handle_event("open_customer_purchases", _, %{assigns: %{selected_customer: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("open_customer_purchases", _, socket) do
    customer = socket.assigns.selected_customer

    case Sales.recent_customer_purchases(socket.assigns.scope, customer.id) do
      {:ok, purchases} ->
        {:noreply,
         socket
         |> assign(:customer_purchases, purchases)
         |> assign(:expanded_purchases, MapSet.new())
         |> assign(:dialog, :customer_purchases)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Customer purchases could not be loaded.")}
    end
  end

  def handle_event("open_checkout", _, socket) do
    if socket.assigns.cart == [] do
      {:noreply, put_flash(socket, :error, "Add a product before continuing.")}
    else
      {:noreply,
       socket
       |> assign(:mobile_cart_open, false)
       |> assign(
         :checkout_stage,
         if(socket.assigns.selected_customer, do: :payment, else: :customer)
       )}
    end
  end

  def handle_event("close_checkout", _, socket),
    do: {:noreply, socket |> assign(:checkout_stage, nil) |> assign(:mobile_cart_open, false)}

  def handle_event("checkout_customer_continue", _, socket),
    do: {:noreply, socket |> assign(:checkout_stage, :payment) |> assign(:mobile_cart_open, false)}

  def handle_event("checkout_payment_back", _, socket),
    do: {:noreply, socket |> assign(:checkout_stage, :customer) |> assign(:mobile_cart_open, false)}

  def handle_event("toggle_delivery", _, socket) do
    if !Scope.allowed?(socket.assigns.scope, "pos.delivery") do
      {:noreply, socket |> clear_delivery() |> sync()}
    else
      socket = assign(socket, :delivery_open, !socket.assigns.delivery_open)

      socket =
        if socket.assigns.delivery_open,
          do: socket,
          else:
            socket
            |> assign(:delivery_custom_input, "")
            |> assign(:delivery_custom_selected, false)
            |> set_delivery_total(0.0)

      {:noreply, sync(socket)}
    end
  end

  def handle_event("set_delivery", %{"amount" => amount}, socket) do
    if !Scope.allowed?(socket.assigns.scope, "pos.delivery") do
      {:noreply, socket |> clear_delivery() |> sync()}
    else
      {:noreply,
       socket
       |> assign(:delivery_open, true)
       |> assign(:delivery_custom_selected, false)
       |> set_delivery_total(float(amount))
       |> sync()}
    end
  end

  def handle_event("change_delivery_amount", %{"value" => amount}, socket) do
    if Scope.allowed?(socket.assigns.scope, "pos.delivery"),
      do: {:noreply, change_custom_delivery_amount(socket, amount)},
      else: {:noreply, socket |> clear_delivery() |> sync()}
  end

  def handle_event("apply_custom_delivery", params, socket) do
    if !Scope.allowed?(socket.assigns.scope, "pos.delivery") do
      {:noreply, socket |> clear_delivery() |> sync()}
    else
      amount = Map.get(params, "value", socket.assigns.delivery_custom_input)
      amount = delivery_amount_input(amount)

      {:noreply,
       socket
       |> assign(:delivery_open, true)
       |> assign(:delivery_custom_input, amount)
       |> assign(:delivery_custom_selected, true)
       |> set_delivery_total(float(amount))
       |> sync()}
    end
  end

  def handle_event("toggle_credit", _, socket) do
    credit = !socket.assigns.credit

    socket =
      socket
      |> assign(:credit, credit)
      |> assign(:credit_due_date, if(credit, do: socket.assigns.credit_due_date, else: ""))

    {:noreply, sync(socket)}
  end

  def handle_event("change_credit_due_date", %{"value" => value}, socket),
    do: {:noreply, socket |> assign(:credit_due_date, value) |> sync()}

  def handle_event("change_credit_due_date", %{"credit_due_date" => value}, socket),
    do: {:noreply, socket |> assign(:credit_due_date, value) |> sync()}

  def handle_event("select_sequence", %{"sequence" => sequence}, socket)
      when sequence in ["CF", "VF", "DV"],
      do: {:noreply, socket |> assign(:sequence, sequence) |> sync()}

  def handle_event("change_memo", params, socket) do
    value = Map.get(params, "additional_info", Map.get(params, "value", ""))
    {:noreply, socket |> assign(:memo, String.slice(value, 0, 1000)) |> sync()}
  end

  def handle_event("restore_pos_draft", draft, socket) do
    {:noreply, restore_pos_draft(socket, draft)}
  end

  def handle_event("add_payment_line", _, socket) do
    previous = List.last(socket.assigns.payments)
    # Tauri's addPaymentLine defaults the first payment to Card and alternates
    # each following line from the preceding method.
    type = if previous && previous.type == "CC", do: "CASH", else: "CC"
    amount = Float.round(max(0.0, total(socket) - paid(socket)), 2)

    payment = %{
      id: "payment-#{System.unique_integer([:positive])}",
      type: type,
      amount: amount,
      split_source: previous && previous.id,
      auto_amount: true
    }

    {:noreply, socket |> assign(:payments, socket.assigns.payments ++ [payment]) |> sync()}
  end

  def handle_event("remove_payment_line", %{"id" => id}, socket),
    do:
      {:noreply,
       socket |> assign(:payments, Enum.reject(socket.assigns.payments, &(&1.id == id))) |> sync()}

  def handle_event("change_payment", %{"id" => id, "field" => field, "value" => value}, socket),
    do: {:noreply, socket |> update_payment(id, field, value) |> sync()}

  def handle_event("open_mobile_cart", _, socket),
    do: {:noreply, assign(socket, :mobile_cart_open, true)}

  def handle_event("close_mobile_cart", _, socket),
    do: {:noreply, assign(socket, :mobile_cart_open, false)}

  def handle_event("complete_sale", params, socket) do
    socket = assign_credit_due_date(socket, params)
    socket = assign_payments_from_params(socket, params)

    if socket.assigns.selected_customer &&
         payment_complete?(socket) do
      change_amount = Float.round(max(0.0, paid(socket) - total(socket)), 2)

      attrs = %{
        "store_id" => socket.assigns.store_id,
        "client_id" => socket.assigns.selected_customer.id,
        "sequence_type" => socket.assigns.sequence,
        "status" => if(socket.assigns.credit, do: "CREDIT", else: "CASH"),
        "due_date" => if(socket.assigns.credit, do: socket.assigns.credit_due_date, else: nil),
        "sale_type" => if(delivery_total(socket) > 0, do: "FOR_DELIVER", else: "IN_SHOP"),
        "delivery_charge" => delivery_total(socket),
        "discount" => order_discount_total(socket),
        "discount_type" => discount_type_for_sale(socket),
        "discount_input" => socket.assigns.order_discount,
        "additional_info" => socket.assigns.memo,
        "lines" =>
          Enum.map(
            socket.assigns.cart,
            &%{
              "product_id" => &1.id,
              "quantity" => &1.qty,
              "discount" => line_discount(&1),
              "discount_type" =>
                if(&1.discount_type == "percent", do: "percentage", else: "money"),
              "discount_input" => &1.discount
            }
          ),
        "payments" =>
          if(socket.assigns.credit,
            do: [],
            else: submitted_payments(socket)
          )
      }

      # Tauri retains a zero-valued split row in the checkout UI, but omits it
      # from the completed sale payload (`.filter(line => line.amount)`).
      # Keep that distinction: the Cash row remains visible until completion,
      # while persistence receives only actual payments.
      attrs =
        Map.update!(
          attrs,
          "payments",
          &Enum.filter(&1, fn payment -> float(payment["amount"]) > 0 end)
        )

      case Sales.create_sale(socket.assigns.scope, attrs) do
        {:ok, sale} ->
          receipt = receipt_payload(sale, current_store(socket))
          receipt = Map.put(receipt, :change_amount, change_amount)

          {:noreply,
           socket
           |> assign(:print_prompt, print_prompt(:receipt, receipt))
           |> assign(:cart, [])
           |> assign(:checkout_stage, nil)
           |> assign(:selected_customer, nil)
           |> assign(:order_discount, 0.0)
           |> assign(:order_discount_mode, "amount")
           |> assign(:delivery, 0.0)
           |> assign(:delivery_open, false)
           |> assign(:delivery_custom_input, "")
           |> assign(:delivery_custom_selected, false)
           |> assign(:credit, false)
           |> assign(:credit_due_date, "")
           |> assign(:payments, [])
           |> assign(:memo, "")
           |> sync()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Sale could not be completed: #{inspect(reason)}")}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "Select a customer, cover the total, and choose a future due date for credit sales."
       )}
    end
  end

  def handle_event("printer_status", _params, socket), do: {:noreply, socket}

  def handle_event("client_info", params, socket),
    do: {:noreply, assign(socket, :client_info, normalize_client_info(params))}

  def handle_event("product_image_persisted", %{"id" => id, "date_create" => date_create}, socket) do
    with product_id when product_id > 0 <- integer(id),
         {:ok, created_at} <- parse_product_image_timestamp(date_create),
         {:ok, _} <- mark_product_image_persisted(socket.assigns.scope.tenant, product_id, created_at) do
      {:noreply,
       update(socket, :products, fn products ->
         Enum.map(products, fn
           %{id: ^product_id, date_create: ^created_at} = product ->
             %{product | image_raw: nil, image_updated_at: product_image_version(created_at)}

           product ->
             product
         end)
       end)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("product_image_persisted", _params, socket), do: {:noreply, socket}

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

  @impl true
  def handle_info({:inventory_changed, %{product_ids: product_ids}}, socket) do
    {:noreply, refresh_inventory_products(socket, product_ids)}
  end

  @impl true
  def render(assigns) do
    # `@socket` is retained as a template-only compatibility alias. It must
    # reflect the current render assigns (not the previous sync snapshot), so
    # delivery changes recalculate checkout totals and payment balances at once.
    assigns = Map.put(assigns, :socket, assigns)

    ~H"""
    <.pos_layout
      id="pos-live"
      class="pos-shell"
      active_page={:pos}
      scope={@scope}
      stores={@stores}
      store_id={@store_id}
      print_relay_token={@print_relay_token}
      phx-hook="PosShell"
      data-mobile-cart-open={to_string(@mobile_cart_open)}
      data-checkout-stage={@checkout_stage || ""}
      data-catalog-view={@catalog_view}
    >
      <:before_layout>
        <svg class="navigation-icon-sprite" aria-hidden="true" focusable="false">
          <symbol
            id="ui-icon-search"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
          >
            <circle cx="11" cy="11" r="6" /><path d="m16 16 4 4" />
          </symbol>
          <symbol
            id="ui-icon-grid"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.25"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <rect x="3" y="3" width="7" height="7" rx="1.5" />
            <rect x="14" y="3" width="7" height="7" rx="1.5" />
            <rect x="3" y="14" width="7" height="7" rx="1.5" />
            <rect x="14" y="14" width="7" height="7" rx="1.5" />
          </symbol>
          <symbol
            id="ui-icon-list"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.25"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <rect x="3" y="5" width="4" height="4" rx="1" />
            <path d="M11 7h10" />
            <rect x="3" y="15" width="4" height="4" rx="1" />
            <path d="M11 17h10" />
          </symbol>
        </svg>
        <div
          :if={message = Phoenix.Flash.get(@flash, :info)}
          id="toast-container"
          class="toast-container"
          data-position="bottom-right"
          aria-label="Notifications"
        >
          <div
            id="discount-order-active"
            class="toast"
            data-variant="info"
            popover="manual"
            phx-hook="FlashToast"
            role="status"
            aria-live="polite"
            aria-atomic="true"
          >
            <div class="toast-content">
              <svg
                class="toast-icon"
                aria-hidden="true"
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <circle cx="12" cy="12" r="10" /><path d="M12 16v-4M12 8h.01" />
              </svg>
              <div class="toast-text">
                <p class="toast-description">{message}</p>
              </div>
              <button
                class="toast-close"
                type="button"
                phx-click="clear_pos_flash"
                aria-label="Dismiss notification"
              >
                ×
              </button>
            </div>
          </div>
        </div>
      </:before_layout>
      <section
        class={["catalog-panel", if(pos_content_loading?(assigns), do: "is-content-loading")]}
        data-view={pos_mobile_view(assigns)}
        data-loading={if(pos_content_loading?(assigns), do: "true", else: "false")}
        aria-labelledby="pos-title"
      >
        <div :if={is_nil(@checkout_stage) and @dialog != :customer_picker} class="catalog-content">
          <header class="topbar">
            <div class="brand-lockup">
              <span class="brand-mark">T</span>
              <div>
                <p class="eyebrow">Tigoo</p>
                <h1 id="pos-title">
                  <span data-i18n="pos.catalog.pointOfSale">Point of Sale</span> — {active_store_name(assigns)}
                </h1>
              </div>
            </div>
            <button
              class="btn mobile-topbar-cart"
              type="button"
              data-variant="outline"
              data-size="icon"
              phx-click="open_mobile_cart"
              aria-label="Open current sale"
            >
              <svg
                aria-hidden="true"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2.25"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <circle cx="9" cy="20" r="1.5" /><circle cx="18" cy="20" r="1.5" /><path d="M3 4h2l2.4 11.2a2 2 0 0 0 2 1.6h7.9a2 2 0 0 0 1.9-1.4L21 8H7" />
              </svg>
              <span :if={items(assigns) > 0} class="mobile-cart-count">{items(assigns)}</span>
            </button>
            <div class="topbar-search">
              <div class="search-field">
                <svg class="search-icon" aria-hidden="true"><use href="#ui-icon-search" /></svg>
                <input
                  id="product-search"
                  class="input"
                  type="search"
                  value={@product_search}
                  phx-keyup="search_products"
                  phx-debounce="0"
                  placeholder="Search products or scan a barcode"
                  data-i18n-placeholder="pos.catalog.searchProducts"
                  autocomplete="off"
                /><button
                  :if={@product_search != ""}
                  class="btn search-clear"
                  type="button"
                  phx-click="clear_product_search"
                >
                  ×
                </button>
              </div>
              <button
                class="btn"
                type="button"
                data-variant="outline"
                data-size="icon"
                phx-click={JS.focus(to: "#product-search")}
                aria-label="Focus product search"
                data-i18n-aria-label="pos.catalog.focusSearch"
              >
                <svg aria-hidden="true"><use href="#ui-icon-search" /></svg>
              </button>
              <button
                class="btn catalog-view-toggle"
                type="button"
                data-variant="outline"
                data-size="icon"
                phx-click="set_catalog_view"
                phx-value-view={if @catalog_view == "cards", do: "table", else: "cards"}
                aria-label={
                  if @catalog_view == "cards", do: "Show table catalog", else: "Show card catalog"
                }
                aria-pressed={to_string(@catalog_view == "table")}
                title={if @catalog_view == "cards", do: "Show table catalog", else: "Show card catalog"}
              >
                <svg :if={@catalog_view == "cards"} aria-hidden="true"><use href="#ui-icon-grid" /></svg>
                <svg :if={@catalog_view == "table"} aria-hidden="true"><use href="#ui-icon-list" /></svg>
              </button>
            </div>
          </header>
          <div class="catalog-heading">
            <div>
              <p class="eyebrow" data-i18n="pos.catalog.catalog">Catalog</p>
              <h2 class="h3" data-i18n="pos.catalog.products">Products</h2>
            </div>
            <p class="products-status" role="status">{product_status(assigns)}</p>
          </div>
          <button class="btn mobile-cart-trigger" type="button" phx-click="open_mobile_cart">
            <span data-i18n="pos.catalog.viewSale">View sale</span>
          </button>
          <div
            id="product-grid"
            class="product-grid"
            aria-live="polite"
            phx-hook="ProductImageCache"
            data-tenant={@scope.tenant}
          >
            <article
              :for={product <- visible_products(assigns)}
              class="card product"
              tabindex="0"
              role="button"
              phx-click="add_product"
              phx-value-id={product.id}
              phx-keydown="add_product"
              phx-key="Enter"
              phx-value-id={product.id}
              aria-label={"Add #{product.name}"}
              data-i18n-aria-label="pos.catalog.addProduct"
              data-i18n-params={Jason.encode!(%{name: product.name})}
            >
              <img
                :if={product_has_image?(product)}
                class="product-image"
                src={product_image_src(product)}
                alt=""
                loading="lazy"
                hidden
                data-product-image-id={product.id}
                data-product-image-cache-key={product_image_version(product.date_create)}
              />
              <div
                :if={not product_has_image?(product) or is_nil(product.image_raw)}
                class="product-image product-image-placeholder"
                aria-hidden="true"
                data-product-image-placeholder={product.id}
              >
                {String.first(product.name || "?")}
              </div>
              <div class="card-content product-content">
                <h2 class="card-title product-name">{product.name || "Unnamed product"}</h2>
                <p class="product-code">
                  {if product.code, do: "SKU #{product.code}", else: "Tap to add"}
                </p>
                <div class="product-footer">
                  <strong class="product-price numeric">{money(float(product.price))}</strong><span class={[
                    "inventory-badge",
                    if(float(product.inventory_quantity) <= 0, do: "inventory-badge-low")
                  ]}><span data-i18n="pos.catalog.stock">Stock</span> {product.inventory_quantity || 0}</span>
                </div>
              </div>
            </article>
            <div id="products-sentinel" phx-hook="InfiniteCatalog" aria-hidden="true">
            </div>
          </div>
          <div
            :if={@catalog_view == "table"}
            id="product-table-wrap"
            class="table-container product-table-container"
            aria-live="polite"
          >
            <table class="table product-table">
              <caption class="table-caption">Catalog products. Select a row to add it to the current sale.</caption>
              <thead>
                <tr class="table-row">
                  <th class="table-head" scope="col">Product</th>
                  <th class="table-head" scope="col">SKU</th>
                  <th class="table-head" scope="col">Stock</th>
                  <th class="table-head product-table-price-head" scope="col">Price</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={product <- visible_products(assigns)}
                  class="table-row product-table-row"
                  tabindex="0"
                  role="button"
                  phx-click="add_product"
                  phx-value-id={product.id}
                  phx-keydown="add_product"
                  phx-key="Enter"
                  aria-label={"Add #{product.name}"}
                >
                  <td class="table-cell product-table-product" data-label="Product">
                    <img
                      :if={product_has_image?(product)}
                      class="product-table-image"
                      src={product_image_src(product)}
                      alt=""
                      loading="lazy"
                      hidden
                      data-product-image-id={product.id}
                      data-product-image-cache-key={product_image_version(product.date_create)}
                    />
                    <span
                      :if={not product_has_image?(product) or is_nil(product.image_raw)}
                      class="product-table-image product-table-image-placeholder"
                      aria-hidden="true"
                      data-product-image-placeholder={product.id}
                    >
                      {String.first(product.name || "?")}
                    </span>
                    <span class="product-table-name">{product.name || "Unnamed product"}</span>
                  </td>
                  <td class="table-cell product-table-muted" data-label="SKU">
                    {if product.code, do: "SKU #{product.code}", else: "Tap to add"}
                  </td>
                  <td class="table-cell" data-label="Stock">
                    <span class={[
                      "inventory-badge",
                      if(float(product.inventory_quantity) <= 0, do: "inventory-badge-low")
                    ]}>
                      <span data-i18n="pos.catalog.stock">Stock</span> {product.inventory_quantity || 0}
                    </span>
                  </td>
                  <td class="table-cell product-table-price numeric" data-label="Price">
                    {money(float(product.price))}
                  </td>
                </tr>
              </tbody>
            </table>
            <div id="products-table-sentinel" phx-hook="InfiniteCatalog" aria-hidden="true"></div>
          </div>
        </div>
        <section
          :if={@dialog == :customer_picker}
          id="customers-screen"
          class="customers-screen"
          aria-labelledby="customers-title"
        >
          <header class="topbar invoice-topbar customers-header">
            <div class="brand-lockup">
              <span class="brand-mark" aria-hidden="true">E</span>
              <div>
                <p class="eyebrow" data-i18n="pos.customers.customers">Customers</p>
                <h2 id="customers-title" class="h3" tabindex="-1" data-i18n="pos.customers.customerList">Customer list</h2>
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
                <span data-i18n="pos.customers.createCustomerTypo">Crear client</span>
              </button><button
                class="btn"
                type="button"
                data-variant="outline"
                phx-click="close_dialog"
              ><span data-i18n="common.back">Back</span></button>
            </div>
          </header>
          <div class="customer-search-field">
            <label class="sr-only" for="customer-search" data-i18n="pos.customers.searchCustomers">Search customers</label>
            <input
              id="customer-search"
              class="input"
              type="search"
              value={@customer_search}
              phx-keyup="search_customers"
              phx-debounce="220"
              phx-mounted={JS.focus(to: "#customer-search")}
              autocomplete="off"
              placeholder="Search customers by name or phone"
              data-i18n-placeholder="pos.customers.searchCustomersPlaceholder"
            />
          </div>
          <p :if={@customers == []} class="customers-status" role="status" data-i18n="pos.customers.noCustomersFound">No customers found.</p>
          <div class="table-container customer-table-container">
            <table class="table customer-table">
              <caption class="table-caption" data-i18n="pos.customers.accountsCaption">Customer accounts and purchase activity.</caption>
              <thead>
                <tr class="table-row">
                  <th class="table-head" scope="col" data-i18n="common.name">Name</th>
                  <th class="table-head" scope="col" data-i18n="common.documentId">Document ID</th>
                  <th class="table-head" scope="col" data-i18n="common.phone">Phone</th>
                  <th class="table-head" scope="col"><span class="sr-only" data-i18n="pos.customers.customerAction">Customer action</span></th>
                </tr>
              </thead>
              <tbody id="customers-table-body">
                <tr :for={customer <- @customers} class="table-row">
                  <td class="table-cell" data-label="Name">{customer.name || "—"}</td>
                  <td class="table-cell" data-label="Document ID">{customer.document_id || "—"}</td>
                  <td class="table-cell" data-label="Phone">{customer.celphone || "—"}</td>
                  <td class="table-cell customer-action">
                    <button
                      class="btn"
                      type="button"
                      data-variant="outline"
                      data-size="sm"
                      phx-click="select_customer"
                      phx-value-id={customer.id}
                      aria-label={"Choose: #{customer.name || "customer"}"}
                    >
                      <span data-i18n="common.choose">Choose</span>
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
        <section
          :if={not is_nil(@checkout_stage) and @dialog != :customer_picker}
          id="checkout-flow"
          class="checkout-flow"
          aria-live="polite"
        >
          <header class="checkout-header">
            <div>
              <p class="eyebrow" data-i18n="pos.checkout.checkout">Checkout</p>
              <h1 id="checkout-title" class="h3">
                <%= if @checkout_stage == :customer do %>
                  <span data-i18n="pos.checkout.customer">Customer</span> — {active_store_name(assigns)}
                <% else %>
                  <span data-i18n="pos.checkout.paymentCompletion">Payment & completion</span> — {active_store_name(assigns)}
                <% end %>
              </h1>
            </div>
            <button class="btn" type="button" data-variant="outline" phx-click="close_checkout">
              <span data-i18n="pos.checkout.backToSale">Back to sale</span>
            </button>
          </header>
          <ol class="checkout-steps" aria-label="Checkout progress" data-i18n-aria-label="pos.checkout.progress">
            <li aria-current={if @checkout_stage == :customer, do: "step"} data-i18n="pos.checkout.stepCustomer">1. Customer</li>
            <li aria-current={if @checkout_stage == :payment, do: "step"} data-i18n="pos.checkout.stepPayment">2. Payment</li>
          </ol>
          <div class="checkout-stage-wrap">
            <section
              :if={@checkout_stage == :customer}
              class="checkout-stage"
              data-stage="customer"
              aria-labelledby="customer-stage-title"
            >
              <div class="checkout-stage-copy">
                <p class="eyebrow" data-i18n="pos.checkout.stepCustomer">1. Customer</p>
                <h2 id="customer-stage-title" class="h2" tabindex="-1" data-i18n="pos.checkout.customer">Customer</h2>
                <button
                  id="customer-picker"
                  class="customer-choice btn"
                  type="button"
                  data-variant="outline"
                  data-i18n={unless @selected_customer, do: "pos.checkout.pickCustomer"}
                  phx-click="open_customer_picker"
                >
                  {(@selected_customer && @selected_customer.name) || gettext("Pick a customer…")}
                </button>
                <div :if={@selected_customer} id="customer-details" class="customer-details">
                  {@selected_customer.name} · {@selected_customer.celphone || ""} · {@selected_customer.address ||
                    ""}
                </div>
              </div>
              <div class="checkout-actions">
                <button class="btn" type="button" data-variant="outline" phx-click="close_checkout">
                  <span data-i18n="common.back">Back</span>
                </button><button
                  id="customer-continue"
                  class="btn"
                  type="button"
                  data-variant="default"
                  phx-click="checkout_customer_continue"
                  disabled={is_nil(@selected_customer)}
                ><span data-i18n="common.continue">Continue</span></button>
              </div>
            </section>
            <section
              :if={@checkout_stage == :payment}
              class="checkout-stage"
              data-stage="payment"
              aria-labelledby="payment-stage-title"
            >
              <div class="checkout-stage-copy">
                <p class="eyebrow" data-i18n="pos.checkout.stepPayment">2. Payment</p>
                <h2 id="payment-stage-title" class="h2" tabindex="-1" data-i18n="pos.checkout.paymentCompletion">Payment & completion</h2>
                <fieldset class="form-fieldset">
                  <legend data-i18n="pos.checkout.sequenceType">Sequence type</legend>
                  <div class="sequence-options" role="group">
                    <div class="sequence-option-buttons">
                      <button
                        :for={sequence <- @sequences}
                        class="btn"
                        type="button"
                        data-variant={if @sequence == sequence.code, do: "default", else: "secondary"}
                        phx-click="select_sequence"
                        phx-value-sequence={sequence.code}
                      >
                        {sequence.name}
                      </button>
                    </div>
                  </div>
                </fieldset>
                <p class="checkout-total-due">
                  <span data-i18n="common.total">Total</span><strong id="checkout-total" class="numeric">{money(total(@socket))}</strong>
                </p>
                <div class="form-group checkout-payment">
                  <button
                    :if={Scope.allowed?(@scope, "pos.delivery")}
                    id="delivery-toggle"
                    class="btn"
                    type="button"
                    data-variant={if @delivery_open, do: "default", else: "outline"}
                    aria-pressed={to_string(@delivery_open)}
                    phx-click="toggle_delivery"
                  >
                    <span data-i18n="pos.checkout.delivery">Delivery</span>
                  </button>
                  <div :if={@delivery_open} id="delivery-options" class="delivery-options">
                    <button
                      :for={amount <- [100, 150, 200]}
                      class="btn"
                      type="button"
                      data-variant={
                        if !@delivery_custom_selected and @delivery == amount,
                          do: "default",
                          else: "secondary"
                      }
                      phx-click="set_delivery"
                      phx-value-amount={amount}
                    >
                      {money(amount)}
                    </button>
                    <form
                      class="delivery-free-control"
                      role="group"
                      aria-label="Delivery free amount"
                      phx-submit="apply_custom_delivery"
                    >
                      <input
                        id="delivery-free-amount"
                        class="input delivery-free-amount"
                        type="number"
                        name="value"
                        min="0"
                        step="0.01"
                        inputmode="decimal"
                        placeholder="Free amount"
                        aria-label="Delivery free amount"
                        data-i18n-placeholder="pos.checkout.freeAmount"
                        data-i18n-aria-label="pos.checkout.deliveryFreeAmount"
                        value={@delivery_custom_input}
                        required
                        phx-input="change_delivery_amount"
                        phx-debounce="300"
                      />
                      <button
                        class="btn delivery-free-check"
                        type="submit"
                        data-variant={if @delivery_custom_selected, do: "default", else: "secondary"}
                        aria-pressed={to_string(@delivery_custom_selected)}
                        aria-label="Select delivery free amount"
                        data-i18n-aria-label="pos.checkout.selectDeliveryFreeAmount"
                      >✓</button>
                    </form>
                    <button
                      :for={amount <- [300, 400, 500, 600]}
                      class="btn"
                      type="button"
                      data-variant={
                        if !@delivery_custom_selected and @delivery == amount,
                          do: "default",
                          else: "secondary"
                      }
                      phx-click="set_delivery"
                      phx-value-amount={amount}
                    >
                      {money(amount)}
                    </button>
                  </div>
                  <button
                    id="credit-toggle"
                    class="btn"
                    type="button"
                    data-variant={if @credit, do: "default", else: "outline"}
                    aria-pressed={to_string(@credit)}
                    phx-click="toggle_credit"
                  >
                    <span data-i18n="pos.checkout.payOnCredit">Pay on Credit</span>
                  </button>
                  <form
                    :if={@credit}
                    id="credit-due-date"
                    class="form-group"
                    phx-submit="complete_sale"
                    phx-hook="CreditDueDateForm"
                  >
                    <label class="label" for="sale-credit-due-date" data-i18n="pos.checkout.dueDate">Due date</label>
                    <input
                      id="sale-credit-due-date"
                      name="credit_due_date"
                      class="input"
                      type="date"
                      value={@credit_due_date}
                      min={future_due_date_min()}
                      required
                      phx-input="change_credit_due_date"
                      phx-change="change_credit_due_date"
                    />
                    <div class="checkout-actions">
                      <button
                        class="btn checkout-back"
                        type="button"
                        data-variant="outline"
                        phx-click="checkout_payment_back"
                      >
                        <span data-i18n="common.back">Back</span>
                      </button><button
                        id="complete-sale"
                        class="btn"
                        type="submit"
                        data-variant="default"
                        disabled
                      ><span data-i18n="common.complete">Complete</span></button>
                    </div>
                  </form>
                  <div :if={!@credit} id="payment-inputs">
                    <fieldset class="form-fieldset">
                      <legend data-i18n="pos.checkout.payments">Payments</legend>
                      <div
                        id="payment-lines"
                        class="payment-lines"
                        phx-hook="PaymentAmounts"
                        data-sale-total={total(@socket)}
                      >
                        <div
                          :for={payment <- @payments}
                          class="payment-line"
                          data-payment-line-id={payment.id}
                          data-split-source={Map.get(payment, :split_source, "")}
                        >
                          <select
                            class="select"
                            phx-change="change_payment"
                            phx-value-id={payment.id}
                            phx-value-field="type"
                          >
                            <option value="CASH" selected={payment.type == "CASH"} data-i18n="common.cash">Cash</option>
                            <option value="CC" selected={payment.type == "CC"} data-i18n="pos.checkout.creditCard">Credit Card</option>
                          </select>
                          <input
                            class="input numeric"
                            type="number"
                            inputmode="decimal"
                            min="0.01"
                            step="0.01"
                            value={payment_amount_input(payment.amount)}
                            data-previous-amount={payment_amount_input(payment.amount)}
                            phx-input="change_payment"
                            phx-value-id={payment.id}
                            phx-value-field="amount"
                          /><button
                            class="btn"
                            type="button"
                            data-variant="ghost"
                            phx-click="remove_payment_line"
                            phx-value-id={payment.id}
                            aria-label="Remove payment"
                            data-i18n-aria-label="pos.checkout.removePayment"
                          >
                            ×
                          </button>
                        </div>
                      </div>
                      <button
                        id="add-payment-line"
                        class="btn"
                        type="button"
                        data-variant="outline"
                        phx-click="add_payment_line"
                      >
                        <span data-i18n="pos.checkout.addPayment">Add payment</span>
                      </button>
                      <p id="payment-balance" class="field-description">
                        <span data-i18n="pos.checkout.remaining">Remaining:</span> {money(remaining(@socket))}
                      </p>
                      <p
                        :if={paid(@socket) > total(@socket)}
                        id="payment-change"
                        class="payment-change"
                        role="status"
                      >
                        <span data-i18n="pos.checkout.change">Change:</span> {money(paid(@socket) - total(@socket))}
                      </p>
                    </fieldset>
                  </div>
                </div>
              </div>
              <div :if={!@credit} class="checkout-actions">
                <button
                  class="btn checkout-back"
                  type="button"
                  data-variant="outline"
                  phx-click="checkout_payment_back"
                >
                  <span data-i18n="common.back">Back</span>
                </button><button
                  id="complete-sale"
                  class="btn"
                  type="button"
                  data-variant="default"
                  phx-click="complete_sale"
                  disabled={!payment_complete?(@socket)}
                ><span data-i18n="common.complete">Complete</span></button>
              </div>
              <div class="form-group checkout-memo">
                <label class="label" for="sale-additional-info" data-i18n="pos.checkout.memoOptional">Memo (optional)</label><textarea
                  id="sale-additional-info"
                  class="input"
                  name="additional_info"
                  rows="3"
                  maxlength="1000"
                  phx-change="change_memo"
                  phx-keyup="change_memo"
                >{@memo}</textarea>
                <p class="field-description" data-i18n="pos.checkout.memoHelp">Up to 1000 characters.</p>
              </div>
            </section>
          </div>
        </section>
      </section>
      <aside
        id="order-panel"
        class={[
          "order-panel",
          if(@mobile_cart_open, do: "is-mobile-open"),
          if(pos_content_loading?(assigns), do: "is-content-loading")
        ]}
        phx-hook="CartAmounts"
        data-order-discount={@order_discount}
        data-order-discount-type={@order_discount_type}
        data-delivery={@delivery}
        data-loading={if(pos_content_loading?(assigns), do: "true", else: "false")}
        aria-labelledby="order-title"
      >
        <header class="order-header">
          <div>
            <p class="eyebrow" data-i18n="pos.cart.currentSale">Current sale</p>
            <div class="customer-picker-wrap">
              <button
                :if={is_nil(@checkout_stage)}
                id="customer-purchases"
                class="btn"
                type="button"
                data-variant="ghost"
                data-size="icon-xs"
                phx-click="open_customer_purchases"
                aria-label="View customer purchases"
                data-i18n-aria-label="pos.cart.viewCustomerPurchases"
                aria-haspopup="dialog"
              >
                <svg
                  aria-hidden="true"
                  width="16"
                  height="16"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <path d="M3 3v18h18" /><path d="M7 16v-4" /><path d="M12 16V8" /><path d="M17 16v-7" />
                </svg>
              </button><button
                id="order-title"
                class="customer-picker"
                type="button"
                data-i18n={unless @selected_customer, do: "pos.checkout.pickCustomerSpaced"}
                phx-click="open_customer_picker"
                disabled={@checkout_stage == :payment}
              >{(@selected_customer && @selected_customer.name) || gettext("Pick a customer …")}</button><button
                :if={@selected_customer && is_nil(@checkout_stage)}
                id="clear-customer"
                class="btn"
                type="button"
                data-variant="ghost"
                data-size="icon-xs"
                phx-click="clear_customer"
                aria-label="Clear customer"
                data-i18n-aria-label="pos.cart.clearCustomer"
              >×</button>
            </div>
          </div>
          <button
            class="btn mobile-cart-close"
            type="button"
            data-variant="ghost"
            data-size="icon"
            phx-click="close_mobile_cart"
            aria-label="Close sale"
            data-i18n-aria-label="pos.cart.closeSale"
          >
            ×
          </button>
          <button
            id="clear-order"
            class="btn"
            type="button"
            data-variant="ghost"
            data-size="sm"
            phx-click="clear_sale_prompt"
            disabled={@cart == []}
          >
            <span data-i18n="common.clear">Clear</span>
          </button>
        </header>
        <p :if={@cart == []} class="cart-empty" data-i18n="pos.cart.empty">Your order is empty. Select a product to begin.</p>
        <div id="cart" class="cart-lines" aria-live="polite">
          <article
            :for={line <- @cart}
            id={"cart-line-#{line.id}"}
            class="cart-line"
            data-cart-item-id={line.id}
            data-price={line.price}
            data-sub={line.sub}
            data-tax={line.tax}
            data-discount={line.discount}
            data-discount-type={line.discount_type}
          >
            <div class="cart-line-head">
              <div>
                <p
                  class="cart-line-name cart-line-discount-trigger"
                  title="Apply a discount to this item"
                  data-i18n-title="pos.cart.discountItem"
                  role="button"
                  tabindex="0"
                  phx-click="open_line_discount"
                  phx-keydown="open_line_discount"
                  phx-value-id={line.id}
                >
                  {line.name}<span :if={line.discount > 0} class="line-discount">{if line.discount_type == "percent", do: "#{line.discount}%", else: money(line.discount)} <span data-i18n="pos.cart.off">off</span></span>
                </p>
                <p class="cart-line-breakdown">
                  <span>
                    <small data-i18n="pos.cart.sub">Sub</small><strong class="numeric">{money(line.sub * line_factor(line))}</strong>
                  </span><span><small data-i18n="common.tax">Tax</small><strong class="numeric">{money(line.tax * line_factor(line))}</strong></span><span><small data-i18n="common.total">Total</small><strong class="numeric">{money(line.price * line_factor(line))}</strong><small data-i18n="pos.cart.each">each</small></span>
                </p>
              </div>
              <button
                class="btn remove-line"
                type="button"
                data-variant="ghost"
                data-size="icon-xs"
                phx-click="remove_line"
                phx-value-id={line.id}
                aria-label={"Remove #{line.name}"}
                data-i18n-aria-label="pos.cart.removeProduct"
                data-i18n-params={Jason.encode!(%{name: line.name})}
                disabled={not is_nil(@checkout_stage)}
              >
                ×
              </button>
            </div>
            <div class="cart-line-footer">
              <div class="quantity-control" role="group">
                <button
                  class="btn"
                  type="button"
                  data-variant="outline"
                  data-size="icon-xs"
                  phx-click="decrease_quantity"
                  phx-value-id={line.id}
                  data-quantity-action="decrease"
                  aria-label="Decrease quantity"
                  data-i18n-aria-label="pos.cart.decreaseQuantity"
                  disabled={not is_nil(@checkout_stage)}
                >
                  −
                </button>
                <input
                  class="quantity-input"
                  type="number"
                  inputmode="numeric"
                  min="1"
                  value={line.qty}
                  phx-change="set_quantity"
                  phx-value-id={line.id}
                  aria-label="Item count"
                  data-i18n-aria-label="pos.cart.itemCount"
                  disabled={not is_nil(@checkout_stage)}
                /><button
                  class="btn"
                  type="button"
                  data-variant="outline"
                  data-size="icon-xs"
                  phx-click="increase_quantity"
                  phx-value-id={line.id}
                  data-quantity-action="increase"
                  aria-label="Increase quantity"
                  data-i18n-aria-label="pos.cart.increaseQuantity"
                  disabled={not is_nil(@checkout_stage)}
                >
                  +
                </button>
              </div>
              <strong
                class="cart-line-total cart-line-discount-trigger numeric"
                title="Apply a discount to this item"
                data-i18n-title="pos.cart.discountItem"
                role="button"
                tabindex="0"
                phx-click="open_line_discount"
                phx-keydown="open_line_discount"
                phx-value-id={line.id}
              >
                {money(line_gross(line) - line_discount(line))}
              </strong>
            </div>
          </article>
        </div>
        <footer class="order-summary">
          <hr class="separator" role="none" />
          <dl class="totals">
            <div>
              <dt data-i18n="common.items">Items</dt>
              <dd>{items(@socket)}</dd>
            </div>
            <div>
              <dt data-i18n="common.subtotal">Subtotal</dt>
              <dd class="numeric">{money(subtotal(@socket))}</dd>
            </div>
            <div>
              <dt data-i18n="common.tax18">Tax (18%)</dt>
              <dd class="numeric">{money(tax(@socket))}</dd>
            </div>
            <div>
              <dt data-i18n="common.discount">Discount</dt>
              <dd class="numeric discount-value">
                −{money(line_discount_total(@socket) + order_discount_total(@socket))}
              </dd>
            </div>
            <div :if={@delivery > 0}>
              <dt data-i18n="pos.checkout.delivery">Delivery</dt>
              <dd class="numeric">{money(@delivery)}</dd>
            </div>
            <div
              class="grand-total order-discount-trigger"
              title="Apply a discount to this sale"
              data-i18n-title="pos.cart.discountSale"
              role="button"
              tabindex="0"
              phx-click="open_order_discount"
              phx-keydown="open_order_discount_key"
              aria-label="Apply order discount. Press Enter."
              data-i18n-aria-label="pos.cart.applyOrderDiscount"
            >
              <dt data-i18n="common.total">Total</dt>
              <dd class="numeric">{money(total(@socket))}</dd>
            </div>
          </dl>
          <div class="payment-label">
            <span data-i18n="pos.checkout.paymentMethod">Payment method</span><span id="payment-choice" class="payment-choice">{payment_choice(@socket)}</span>
          </div>
          <button
            :if={is_nil(@checkout_stage)}
            id="start-checkout"
            class="btn charge-button"
            type="button"
            data-variant="default"
            data-size="lg"
            phx-click="open_checkout"
            disabled={@cart == []}
          >
            <span data-i18n="common.continue">Continue</span>
          </button>
        </footer>
      </aside>
      <button
        :if={@mobile_cart_open}
        class="mobile-cart-backdrop is-visible"
        type="button"
        phx-click="close_mobile_cart"
        aria-label="Close sale"
        data-i18n-aria-label="pos.cart.closeSale"
      >
      </button>
      <dialog :if={@dialog == :clear_sale} open class="dialog" data-size="sm">
        <div class="dialog-content">
          <div class="dialog-header">
            <h2 class="dialog-title" data-i18n="pos.cart.clearTitle">Clear this order?</h2>
            <p class="dialog-description" data-i18n="pos.cart.clearDescription">All items and line discounts will be removed.</p>
          </div>
          <div class="dialog-footer">
            <button class="btn" type="button" data-variant="outline" phx-click="close_dialog">
              <span data-i18n="common.cancel">Cancel</span>
            </button><button
              class="btn"
              type="button"
              data-variant="destructive"
              phx-click="clear_sale"
            ><span data-i18n="pos.cart.clearOrder">Clear order</span></button>
          </div>
        </div>
      </dialog>
      <.customer_dialog
        :if={@customer_dialog?}
        status={@customer_form_status}
        saving={@saving_customer?}
      />
      <dialog
        :if={@dialog == :discount}
        id="discount-dialog"
        class="dialog"
        data-size="sm"
        phx-hook="DiscountDialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="discount-title"
      >
        <div class="dialog-content">
          <div class="dialog-header">
            <div class="discount-heading">
              <div>
                <p class="eyebrow">
                  {if @discount_target, do: "Line item discount", else: "Order discount"}
                </p>
                <h2 id="discount-title" class="dialog-title">
                  {if @discount_target, do: "Apply a discount", else: "Apply an order discount"}
                </h2>
                <p class="dialog-description">{discount_subject(assigns)}</p>
              </div>
              <img
                :if={discount_image(assigns)}
                class="discount-product-image"
                src={discount_image(assigns)}
                alt=""
              />
            </div>
          </div>
          <form
            id="discount-form"
            class="form"
            phx-hook="DiscountPreview"
            phx-submit="apply_discount"
            data-discount-base={discount_base(assigns)}
            data-discount-type={@discount_type}
            data-discount-target={if @discount_target, do: "line", else: "order"}
          >
            <input id="discount-type" name="discount_type" type="hidden" value={@discount_type} />
            <div class="discount-switch" role="group" aria-label="Discount type" data-i18n-aria-label="pos.discount.type">
              <button
                class="btn"
                type="button"
                data-discount-type="percent"
                data-variant={if @discount_type == "percent", do: "default", else: "secondary"}
                aria-pressed={to_string(@discount_type == "percent")}
              >
                %
              </button><button
                class="btn"
                type="button"
                data-discount-type="amount"
                data-variant={if @discount_type == "amount", do: "default", else: "secondary"}
                aria-pressed={to_string(@discount_type == "amount")}
              >$</button><button
                class="btn"
                type="button"
                data-discount-type="final_price"
                data-variant={if @discount_type == "final_price", do: "default", else: "secondary"}
                aria-pressed={to_string(@discount_type == "final_price")}
                title="Price after discount"
              >=</button>
            </div>
            <div class="form-field">
              <label id="discount-input-label" class="label" for="discount-input">
                {discount_input_label(@discount_type)}
              </label>
              <div class="form-field-inline">
                <input
                  id="discount-input"
                  class="input numeric"
                  style="flex: 1"
                  name="value"
                  type="number"
                  inputmode="decimal"
                  min="0"
                  max={discount_input_max(assigns)}
                  step="0.01"
                  value={@discount_input}
                /><button class="btn" type="button" data-variant="outline" data-clear-discount>
                  <span data-i18n="common.clear">Clear</span>
                </button>
              </div>
              <p id="discount-help" class="field-description">
                {discount_help(@discount_type, @discount_target)}
              </p>
            </div>
            <dl class="discount-preview">
              <div>
                <dt data-i18n="pos.discount.amountLabel">Amount</dt>
                <dd class="numeric">{money(discount_base(assigns))}</dd>
              </div>
              <div>
                <dt data-i18n="common.discount">Discount</dt>
                <dd class="numeric">−{money(discount_preview(assigns))}</dd>
              </div>
              <div>
                <dt data-i18n="pos.discount.afterDiscount">After discount</dt>
                <dd class="numeric">{money(discount_base(assigns) - discount_preview(assigns))}</dd>
              </div>
            </dl>
            <div class="dialog-footer">
              <button class="btn" type="button" data-variant="outline" phx-click="close_dialog">
                <span data-i18n="common.cancel">Cancel</span>
              </button><button class="btn" type="submit" data-variant="default"><span data-i18n="pos.discount.applyDiscount">Apply discount</span></button>
            </div>
          </form>
        </div>
      </dialog>
      <dialog
        :if={@dialog == :customer_purchases}
        id="customer-purchases-dialog"
        class="dialog"
        data-size="xl"
        phx-hook="DiscountDialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="customer-purchases-title"
      >
        <div class="dialog-content">
          <div class="dialog-header">
            <h2 id="customer-purchases-title" class="dialog-title">
              {@selected_customer.name} — recent purchases
            </h2>
            <p class="dialog-description">The 10 most recent purchases, newest first.</p>
          </div>
          <div class="dialog-body">
            <p :if={@customer_purchases == []} class="customers-status" role="status">
              No purchases found.
            </p>
            <div class="table-container">
              <table class="table">
                <caption class="table-caption">
                  Customer purchase history. Expand an item count to view the sold items.
                </caption>
                <thead>
                  <tr class="table-row">
                    <th class="table-head" scope="col">Date</th>
                    <th class="table-head" scope="col">Salesperson</th>
                    <th class="table-head" scope="col">Items</th>
                    <th class="table-head" scope="col">Status</th>
                    <th class="table-head" scope="col" style="text-align:right">Total</th>
                  </tr>
                </thead>
                <tbody id="customer-purchases-body" phx-hook="CustomerPurchases">
                  <%= for purchase <- @customer_purchases do %>
                    <tr class="table-row">
                      <td class="table-cell">{purchase_date(purchase.date_create)}</td>
                      <td class="table-cell">{purchase.salesperson || "—"}</td>
                      <td class="table-cell">
                        <button
                          class="btn customer-purchase-detail-trigger"
                          type="button"
                          data-variant="ghost"
                          data-customer-purchase-details={purchase.id}
                          aria-expanded="false"
                          aria-controls={"customer-purchase-items-#{purchase.id}"}
                        >
                          <span class="customer-purchase-disclosure" aria-hidden="true">▸</span>Items ({length(
                            purchase.items
                          )})
                        </button>
                      </td>
                      <td class="table-cell">{purchase.invoice_status || purchase.status || "—"}</td>
                      <td class="table-cell numeric" style="text-align:right">
                        {money(float(purchase.amount))}
                      </td>
                    </tr>
                    <tr
                      id={"customer-purchase-items-#{purchase.id}"}
                      class="table-row customer-purchase-details-row"
                      hidden
                    >
                      <td class="table-cell" colspan="5">
                        <table class="table customer-purchase-items-table">
                          <caption class="sr-only">
                            Items on {purchase.sequence || "sale #{purchase.id}"}
                          </caption>
                          <thead>
                            <tr class="table-row">
                              <th class="table-head" scope="col">Item</th>
                              <th class="table-head" scope="col">Quantity</th>
                              <th class="table-head" scope="col">Price</th>
                              <th class="table-head" scope="col">Discount</th>
                              <th class="table-head" scope="col">Total</th>
                            </tr>
                          </thead>
                          <tbody>
                            <tr :for={item <- purchase.items} class="table-row">
                              <td class="table-cell">{item.name || "Product ##{item.product_id}"}</td>
                              <td class="table-cell">{item.quantity}</td>
                              <td class="table-cell numeric">{money(float(item.price))}</td>
                              <td class="table-cell numeric">{purchase_discount(item)}</td>
                              <td class="table-cell numeric">{money(float(item.total))}</td>
                            </tr>
                          </tbody>
                        </table>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
          <div class="dialog-footer">
            <button class="btn" type="button" data-variant="outline" phx-click="close_dialog">
              Close
            </button>
          </div>
        </div>
      </dialog>
      <.print_dialog :if={@print_prompt} prompt={@print_prompt} />
    </.pos_layout>
    """
  end

  defp load_products(%{assigns: %{loading_products: true}} = socket), do: socket
  defp load_products(%{assigns: %{has_more: false}} = socket), do: socket

  defp load_products(socket) do
    if !Scope.allowed?(socket.assigns.scope, "product.view") do
      socket
      |> assign(:products, [])
      |> assign(:cursor, nil)
      |> assign(:has_more, false)
      |> assign(:loading_products, false)
    else
      load_visible_products(socket)
    end
  end

  defp load_visible_products(socket) do
    assign(socket, :loading_products, true)

    case Sql.active_products_page(socket.assigns.cursor,
           store_id: socket.assigns.store_id,
           limit: 50
         ) do
      {:ok, page} ->
        socket
        |> assign(
          :products,
          socket.assigns.products ++
            Enum.map(page.entries, &normalize_product/1)
        )
        |> assign(:cursor, page.next_cursor)
        |> assign(:has_more, page.has_more?)
        |> assign(:loading_products, false)

      {:error, _} ->
        socket
        |> assign(:loading_products, false)
        |> put_flash(:error, "Products could not be loaded.")
    end
  end

  # InventoryEvents carries only product ids. Fetching just the affected loaded
  # products keeps every terminal current without reloading or disturbing the
  # catalog's cursor, search, or cart state.
  defp refresh_inventory_products(socket, product_ids) do
    changed = MapSet.new(product_ids)

    products =
      Enum.flat_map(socket.assigns.products, fn product ->
        if MapSet.member?(changed, product.id) do
          case Sql.active_product(product.id, socket.assigns.store_id) do
            {:ok, nil} -> []
            {:ok, fresh} -> [normalize_product(fresh)]
            {:error, _} -> [product]
          end
        else
          [product]
        end
      end)

    loaded_ids = MapSet.new(Enum.map(socket.assigns.products, & &1.id))

    new_products =
      changed
      |> MapSet.difference(loaded_ids)
      |> Enum.flat_map(fn product_id ->
        case Sql.active_product(product_id, socket.assigns.store_id) do
          {:ok, fresh} when is_map(fresh) ->
            [normalize_product(fresh)]
          _ -> []
        end
      end)

    assign(socket, :products, new_products ++ products)
  end

  defp load_customers(socket) do
    case Sql.recent_clients_page(nil, socket.assigns.customer_search, limit: 100) do
      {:ok, page} -> assign(socket, :customers, Enum.map(page.entries, &normalize_customer/1))
      _ -> assign(socket, :customers, [])
    end
  end

  defp restore_pos_draft(socket, %{"store_id" => store_id} = draft) do
    if to_string(store_id) == to_string(socket.assigns.store_id) do
      socket
      |> assign(:cart, restore_cart(Map.get(draft, "cart", []), socket.assigns.store_id))
      |> assign(:selected_customer, restore_customer(Map.get(draft, "selected_customer")))
      |> assign(:order_discount, float(Map.get(draft, "order_discount")))
      |> assign(:order_discount_type, discount_type(Map.get(draft, "order_discount_type")))
      |> assign(:order_discount_mode, discount_mode(Map.get(draft, "order_discount_mode")))
      |> restore_delivery(draft)
      |> assign(:credit, truthy?(Map.get(draft, "credit")))
      |> assign(:credit_due_date, text(Map.get(draft, "credit_due_date")))
      |> assign(:payments, restore_payments(Map.get(draft, "payments", [])))
      |> assign(:sequence, sequence(Map.get(draft, "sequence")))
      |> assign(:memo, String.slice(text(Map.get(draft, "memo")), 0, 1000))
      |> sync()
    else
      socket
    end
  end

  defp restore_pos_draft(socket, _), do: socket

  defp restore_delivery(socket, draft) do
    if Scope.allowed?(socket.assigns.scope, "pos.delivery") do
      socket
      |> assign(:delivery, max(0.0, float(Map.get(draft, "delivery"))))
      |> assign(:delivery_open, truthy?(Map.get(draft, "delivery_open")))
      |> assign(:delivery_custom_input, delivery_amount_input(Map.get(draft, "delivery_custom_input", "")))
      |> assign(:delivery_custom_selected, truthy?(Map.get(draft, "delivery_custom_selected")))
    else
      clear_delivery(socket)
    end
  end

  defp restore_cart(lines, store_id) when is_list(lines) do
    Enum.flat_map(lines, fn line ->
      with product_id when product_id > 0 <- integer(value(line, :id) || value(line, :product_id)),
           {:ok, product} when is_map(product) <- Sql.active_product(product_id, store_id) do
        product = normalize_product(product)

        [
          %{
            id: product.id,
            name: product.name || "Unnamed product",
            price: float(product.price),
            sub: float(product.sub),
            tax: float(product.tax),
            image_raw: product.image_raw,
            qty: max(1, integer(value(line, :qty))),
            discount: max(0.0, float(value(line, :discount))),
            discount_type: discount_type(value(line, :discount_type)),
            discount_mode: discount_mode(value(line, :discount_mode) || value(line, :discount_type))
          }
        ]
      else
        _ -> []
      end
    end)
  end

  defp restore_cart(_, _), do: []

  defp restore_customer(nil), do: nil

  defp restore_customer(customer) when is_map(customer) do
    customer
    |> normalize_customer()
    |> then(fn normalized -> if normalized.id, do: normalized, else: nil end)
  end

  defp restore_customer(_), do: nil

  defp restore_payments(payments) when is_list(payments) do
    Enum.flat_map(payments, fn payment ->
      amount = max(0.0, float(value(payment, :amount)))

      if amount > 0 do
        [
          %{
            id: text(value(payment, :id), "payment-#{System.unique_integer([:positive])}"),
            type: payment_type(value(payment, :type)),
            amount: amount,
            split_source: value(payment, :split_source),
            auto_amount: truthy?(value(payment, :auto_amount))
          }
        ]
      else
        []
      end
    end)
  end

  defp restore_payments(_), do: []

  defp draft_payload(assigns) do
    %{
      store_id: assigns.store_id,
      cart:
        Enum.map(assigns.cart, fn line ->
          %{
            id: line.id,
            qty: line.qty,
            discount: line.discount,
            discount_type: line.discount_type,
            discount_mode: Map.get(line, :discount_mode, line.discount_type)
          }
        end),
      selected_customer: assigns.selected_customer,
      order_discount: assigns.order_discount,
      order_discount_type: assigns.order_discount_type,
      order_discount_mode: Map.get(assigns, :order_discount_mode, assigns.order_discount_type),
      delivery: assigns.delivery,
      delivery_open: assigns.delivery_open,
      delivery_custom_input: assigns.delivery_custom_input,
      delivery_custom_selected: assigns.delivery_custom_selected,
      credit: assigns.credit,
      credit_due_date: assigns.credit_due_date,
      payments: assigns.payments,
      sequence: assigns.sequence,
      memo: assigns.memo
    }
  end

  defp add_product(socket, p) do
    cart =
      case Enum.find_index(socket.assigns.cart, &(&1.id == p.id)) do
        nil ->
          socket.assigns.cart ++
            [
              %{
                id: p.id,
                name: p.name || "Unnamed product",
                price: float(p.price),
                sub: float(p.sub),
                tax: float(p.tax),
                image_raw: p.image_raw,
                image_updated_at: p.image_updated_at,
                qty: 1,
                discount: 0.0,
                discount_type: "amount",
                discount_mode: "amount"
              }
            ]

        index ->
          List.update_at(
            socket.assigns.cart,
            index,
            &Map.update!(&1, :qty, fn qty -> qty + 1 end)
          )
      end

    assign(socket, :cart, cart)
  end

  defp change_quantity(socket, id, delta),
    do:
      Enum.find(socket.assigns.cart, &(to_string(&1.id) == id))
      |> then(fn line ->
        if line, do: set_quantity(socket, id, line.qty + delta), else: socket
      end)

  defp set_quantity(socket, id, qty),
    do:
      if(qty < 1,
        do:
          assign(socket, :cart, Enum.reject(socket.assigns.cart, &(to_string(&1.id) == id)))
          |> sync(),
        else:
          assign(
            socket,
            :cart,
            Enum.map(socket.assigns.cart, fn line ->
              if to_string(line.id) == id, do: %{line | qty: qty}, else: line
            end)
          )
          |> sync()
      )

  defp apply_discount(socket, value) do
    discount_target = socket.assigns.discount_target

    discount_type =
      if socket.assigns.discount_type == "final_price",
        do: "amount",
        else: socket.assigns.discount_type

    socket =
      if socket.assigns.discount_target do
        assign(
          socket,
          :cart,
          Enum.map(socket.assigns.cart, fn line ->
            if(to_string(line.id) == socket.assigns.discount_target,
              do:
                Map.merge(line, %{
                  discount: value,
                  discount_type: discount_type,
                  discount_mode: socket.assigns.discount_type
                }),
              else: line
            )
          end)
        )
      else
        socket
        |> assign(:order_discount, value)
        |> assign(:order_discount_type, discount_type)
        |> assign(:order_discount_mode, socket.assigns.discount_type)
        |> assign(
          :cart,
          Enum.map(
            socket.assigns.cart,
            &Map.merge(&1, %{discount: 0.0, discount_type: "amount", discount_mode: "amount"})
          )
        )
      end

    socket = socket |> assign(:dialog, nil) |> sync()

    if discount_target,
      do: push_event(socket, "pos:cart-bump", %{id: discount_target}),
      else: socket
  end

  defp change_custom_delivery_amount(socket, amount) do
    amount = delivery_amount_input(amount)

    socket =
      socket
      |> assign(:delivery_open, true)
      |> assign(:delivery_custom_input, amount)
      |> assign(:delivery_custom_selected, false)

    socket
  end

  defp delivery_amount_input(value) do
    value = value |> to_string() |> String.trim()

    case Float.parse(value) do
      {amount, ""} when amount >= 0 -> value
      _ -> ""
    end
  end

  defp update_payment(socket, id, "type", value),
    do:
      assign(
        socket,
        :payments,
        Enum.map(socket.assigns.payments, fn p ->
          if p.id == id, do: %{p | type: value}, else: p
        end)
      )

  defp update_payment(socket, id, "amount", value) do
    entered = max(0.0, float(value))
    payment = Enum.find(socket.assigns.payments, &(&1.id == id))

    payments =
      if payment do
        previous = payment.amount
        change = Float.round(entered - previous, 2)
        total_before_change = paid(socket) - entered + previous

        # Once an amount is typed by the cashier it is no longer the
        # automatically-filled balance line. Delivery changes must preserve
        # this explicit split and only refresh the remaining automatic line.
        payments =
          Enum.map(socket.assigns.payments, fn p ->
            if p.id == id,
              do: p |> Map.put(:amount, entered) |> Map.put(:auto_amount, false),
              else: p
          end)

        case Map.get(payment, :split_source) &&
               Enum.find(payments, &(&1.id == payment.split_source)) do
          nil ->
            payments

          source ->
            change_absorbed =
              if change < 0,
                do: min(-change, max(0.0, total_before_change - total(socket))),
                else: 0.0

            transferred =
              if change > 0, do: min(change, source.amount), else: change + change_absorbed

            Enum.map(payments, fn p ->
              if p.id == source.id,
                do: %{p | amount: Float.round(max(0.0, p.amount - transferred), 2)},
                else: p
            end)
        end
      else
        socket.assigns.payments
      end

    assign(socket, :payments, payments)
  end

  defp update_payment(socket, _, _, _), do: socket

  # Tauri keeps an untouched initial payment populated with the balance due.
  # Delivery changes the sale total, so refresh that one automatic line while
  # retaining every amount the cashier has explicitly entered for a split.
  defp set_delivery_total(socket, delivery) do
    socket = assign(socket, :delivery, max(0.0, delivery))

    # A single payment is the balance line produced by Tauri's “Add payment”.
    # It remains the balance line until the cashier creates a split. Do not
    # depend on an input event marker here: LiveView can emit an input event
    # while restoring the number control, even when the cashier did not edit it.
    automatic_payment =
      case socket.assigns.payments do
        [payment] -> payment
        payments -> Enum.find(payments, fn payment -> Map.get(payment, :auto_amount, false) end)
      end

    payments =
      case automatic_payment do
        nil ->
          socket.assigns.payments

        payment ->
          paid_by_other_lines =
            socket.assigns.payments
            |> Enum.reject(&(&1.id == payment.id))
            |> Enum.sum_by(& &1.amount)

          amount = Float.round(max(0.0, total(socket) - paid_by_other_lines), 2)

          Enum.map(socket.assigns.payments, fn line ->
            if line.id == payment.id, do: %{line | amount: amount}, else: line
          end)
      end

    assign(socket, :payments, payments)
  end

  defp clear_delivery(socket) do
    socket
    |> assign(:delivery, 0.0)
    |> assign(:delivery_open, false)
    |> assign(:delivery_custom_input, "")
    |> assign(:delivery_custom_selected, false)
  end

  defp delivery_total(socket),
    do: if(Scope.allowed?(socket.assigns.scope, "pos.delivery"), do: socket.assigns.delivery, else: 0.0)

  defp line_gross(line), do: line.price * line.qty

  defp line_discount(line),
    do:
      if(line.discount_type == "percent",
        do: line_gross(line) * min(line.discount, 100) / 100,
        else: min(line.discount, line_gross(line))
      )

  defp line_factor(line),
    do:
      if(line_gross(line) == 0,
        do: 1,
        else: (line_gross(line) - line_discount(line)) / line_gross(line)
      )

  defp subtotal(state),
    do:
      Enum.sum(
        Enum.map(state(state).cart, fn line ->
          line.sub * line.qty * line_factor(line) * order_factor(state)
        end)
      )

  defp line_discount_total(state), do: Enum.sum(Enum.map(state(state).cart, &line_discount/1))
  defp gross_subtotal(state), do: Enum.sum(Enum.map(state(state).cart, &line_gross/1))
  defp before_order_discount(state), do: gross_subtotal(state) - line_discount_total(state)

  defp order_discount_total(state),
    do:
      if(state(state).order_discount_type == "percent",
        do: before_order_discount(state) * min(state(state).order_discount, 100) / 100,
        else: min(state(state).order_discount, before_order_discount(state))
      )

  defp discount_type_for_sale(state),
    do: if(state(state).order_discount_type == "percent", do: "percentage", else: "money")

  defp merchandise_total(state), do: before_order_discount(state) - order_discount_total(state)
  defp total(state), do: merchandise_total(state) + state(state).delivery

  defp order_factor(state),
    do:
      if(before_order_discount(state) == 0,
        do: 1,
        else: merchandise_total(state) / before_order_discount(state)
      )

  defp tax(state),
    do:
      Enum.sum(
        Enum.map(state(state).cart, fn line ->
          line.tax * line.qty * line_factor(line) * order_factor(state)
        end)
      )

  defp items(state), do: Enum.sum(Enum.map(state(state).cart, & &1.qty))
  defp paid(state), do: Enum.sum(Enum.map(state(state).payments, & &1.amount))
  defp remaining(socket), do: max(0.0, total(socket) - paid(socket))

  defp payment_choice(state) do
    if state(state).credit do
      "Credit"
    else
      state(state).payments
      |> Enum.map(fn payment -> if payment.type == "CC", do: "Credit Card", else: "Cash" end)
      |> Enum.uniq()
      |> Enum.join(" + ")
      |> case do
        "" -> "—"
        value -> value
      end
    end
  end

  defp payment_amount_input(value), do: :erlang.float_to_binary(float(value), decimals: 2)

  defp assign_credit_due_date(socket, %{"credit_due_date" => value}),
    do: assign(socket, :credit_due_date, value)

  defp assign_credit_due_date(socket, _params), do: socket

  defp assign_payments_from_params(socket, %{"payments" => payments}) when is_list(payments) do
    payments =
      payments
      |> Enum.flat_map(fn
        %{"type" => type, "amount" => amount} when type in ["CASH", "CC"] ->
          amount = Float.round(max(0.0, float(amount)), 2)

          if amount > 0,
            do: [%{id: "payment-submit-#{System.unique_integer([:positive])}", type: type, amount: amount}],
            else: []

        _ ->
          []
      end)

    assign(socket, :payments, payments)
  end

  defp assign_payments_from_params(socket, _params), do: socket

  defp submitted_payments(socket) do
    socket.assigns.payments
    |> Enum.reduce({[], total(socket)}, fn payment, {payments, remaining} ->
      amount = Float.round(min(payment.amount, max(0.0, remaining)), 2)
      payment = %{"type" => payment.type, "amount" => amount}

      {[payment | payments], Float.round(remaining - amount, 2)}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp payment_complete?(state) do
    state = state(state)

    if state.credit do
      future_due_date?(state.credit_due_date)
    else
      paid(state) >= total(state)
    end
  end

  defp future_due_date_min, do: Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

  defp future_due_date?(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, due_date} -> Date.compare(due_date, Date.utc_today()) == :gt
      _ -> false
    end
  end

  defp future_due_date?(_), do: false

  defp float(value) when is_number(value), do: value * 1.0
  defp float(%Decimal{} = value), do: Decimal.to_float(value)

  defp float(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _remainder} -> number
      :error -> 0.0
    end
  end

  defp float(_), do: 0.0
  defp integer(value) when is_integer(value), do: value

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, _} -> number
      :error -> 0
    end
  end

  defp integer(_), do: 0

  defp truthy?(value), do: value in [true, "true", 1, "1"]
  defp text(value, fallback \\ "")
  defp text(value, _fallback) when is_binary(value), do: value
  defp text(nil, fallback), do: fallback
  defp text(value, _fallback), do: to_string(value)

  defp discount_type("percent"), do: "percent"
  defp discount_type(_), do: "amount"

  defp discount_mode("percent"), do: "percent"
  defp discount_mode("final_price"), do: "final_price"
  defp discount_mode(_), do: "amount"

  defp discount_value("final_price", raw_value, final_price, base) when is_binary(raw_value),
    do:
      if(String.trim(raw_value) == "",
        do: 0.0,
        else: discount_value("final_price", :entered, final_price, base)
      )

  defp discount_value("final_price", nil, _final_price, _base),
    do: 0.0

  defp discount_value("final_price", _raw_value, final_price, base),
    do: Float.round(max(0.0, base - final_price), 2)

  defp discount_value(_, _raw_value, discount, _base), do: discount

  defp payment_type("CC"), do: "CC"
  defp payment_type(_), do: "CASH"

  defp sequence(sequence) when sequence in ["CF", "VF", "DV"], do: sequence
  defp sequence(_), do: "CF"

  defp discount_input_value(value, _mode, _base) when value == 0 or value == 0.0, do: ""

  defp discount_input_value(value, "final_price", base),
    do: :erlang.float_to_binary(max(0.0, base - value), decimals: 2)

  defp discount_input_value(value, _mode, _base), do: :erlang.float_to_binary(value, decimals: 2)

  defp purchase_date(%NaiveDateTime{} = value), do: Calendar.strftime(value, "%Y-%m-%d %H:%M")
  defp purchase_date(_), do: "—"

  defp purchase_discount(item) do
    discount = float(item.discount)

    cond do
      discount == 0 ->
        "—"

      item.discount_type == "percentage" and not is_nil(item.discount_input) ->
        "#{float(item.discount_input)}%"

      true ->
        money(discount)
    end
  end

  defp sequence_options(tenant) do
    sequences =
      Repo.all(
        from(sequence in Sequence,
          where: sequence.code in ["CF", "VF", "DV"],
          order_by: [asc: sequence.code],
          select: %{code: sequence.code, name: sequence.name}
        ),
        prefix: tenant
      )

    sequence_names = Map.new(sequences, &{&1.code, &1.name})

    Enum.map(default_sequence_options(), fn sequence ->
      %{sequence | name: Map.get(sequence_names, sequence.code, sequence.name)}
    end)
  end

  defp default_sequence_options do
    [
      %{code: "CF", name: "Consumer final"},
      %{code: "DV", name: "Direct sale"},
      %{code: "VF", name: "Fiscal voucher"}
    ]
  end

  defp visible_products(assigns) do
    query = String.downcase(String.trim(assigns.product_search))

    if query == "",
      do: assigns.products,
      else:
        Enum.filter(assigns.products, fn product ->
          String.contains?(String.downcase("#{product.name || ""} #{product.code || ""}"), query)
        end)
  end

  defp product_status(assigns) do
    cond do
      assigns.loading_products and assigns.products == [] -> "Loading products…"
      assigns.product_search != "" and visible_products(assigns) == [] -> "No matching products."
      assigns.has_more -> "Scroll for more products"
      true -> "#{length(assigns.products)} products loaded"
    end
  end

  defp pos_content_loading?(assigns), do: assigns.loading_products and assigns.products == []

  defp initial_catalog_view(socket) do
    if connected?(socket) do
      case get_connect_params(socket) do
        %{"catalog_view" => view} when view in ["cards", "table"] -> view
        _ -> "cards"
      end
    else
      "cards"
    end
  end

  defp image_source("data:image/" <> _ = source), do: source
  defp image_source(source), do: "data:image/jpeg;base64,#{source}"

  defp product_image_src(%{image_raw: image}) when is_binary(image) and image != "",
    do: image_source(image)

  defp product_image_src(_product), do: nil

  defp product_has_image?(product),
    do: nonempty_string?(value(product, :image_raw)) or not is_nil(value(product, :image_updated_at))

  defp product_image_version(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp product_image_version({{_, _, _}, {_, _, _}} = value) do
    value
    |> NaiveDateTime.from_erl!()
    |> NaiveDateTime.to_iso8601()
  end

  defp product_image_version(value) when is_binary(value), do: value

  defp product_image_version(product) when is_map(product),
    do: product_image_version(value(product, :image_updated_at))

  defp product_image_version(_value), do: nil

  defp product_with_image(%{image_raw: image} = product, _store_id)
       when is_binary(image) and image != "",
    do: product

  defp product_with_image(product, store_id) do
    case Sql.active_product(product.id, store_id) do
      {:ok, fresh} when is_map(fresh) -> normalize_product(fresh)
      _ -> product
    end
  end

  defp parse_product_image_timestamp(value) do
    value
    |> product_image_version()
    |> case do
      nil -> :error
      value -> NaiveDateTime.from_iso8601(value)
    end
  end

  defp mark_product_image_persisted(tenant, product_id, created_at) do
    from(product in Product,
      where: product.id == ^product_id and product.date_create == ^created_at,
      update: [set: [image_updated_at: ^created_at]]
    )
    |> Repo.update_all([], prefix: tenant)
    |> case do
      {1, _} -> {:ok, :updated}
      {0, _} -> {:error, :not_found}
    end
  end

  defp nonempty_string?(value), do: is_binary(value) and value != ""

  defp active_store_name(assigns),
    do:
      Enum.find_value(assigns.stores, "", fn store ->
        if store.id == assigns.store_id, do: store.name
      end)

  defp pos_mobile_view(%{dialog: :customer_picker}), do: "customers"
  defp pos_mobile_view(%{checkout_stage: stage}) when not is_nil(stage), do: "checkout"
  defp pos_mobile_view(_assigns), do: "catalog"

  defp discount_line(assigns),
    do: Enum.find(assigns.cart, &(to_string(&1.id) == assigns.discount_target))

  defp discount_image(assigns) do
    case discount_line(assigns) do
      %{image_raw: image} when is_binary(image) -> image_source(image)
      _ -> nil
    end
  end

  defp discount_subject(assigns) do
    case discount_line(assigns) do
      %{name: name} -> name
      _ -> "Choose a percentage or amount for this order."
    end
  end

  defp discount_base(assigns) do
    case discount_line(assigns) do
      nil -> before_order_discount(assigns)
      line -> line_gross(line)
    end
  end

  defp discount_preview(assigns) do
    entered = float(assigns.discount_input)
    base = discount_base(assigns)

    case assigns.discount_type do
      "percent" -> base * min(entered, 100) / 100
      "final_price" -> discount_value("final_price", assigns.discount_input, min(entered, base), base)
      _ -> min(entered, base)
    end
  end

  defp discount_input_label("percent"), do: "Discount percentage"
  defp discount_input_label("final_price"), do: "Price after discount"
  defp discount_input_label(_), do: "Discount amount"

  defp discount_input_max(assigns) do
    cond do
      assigns.discount_type == "percent" -> "100"
      assigns.discount_type == "final_price" -> :erlang.float_to_binary(discount_base(assigns), decimals: 2)
      true -> nil
    end
  end

  defp discount_help("percent", _target), do: "Enter 0 to remove this discount."
  defp discount_help("final_price", target) when is_binary(target), do: "Enter the final price for this entire order line."
  defp discount_help("final_price", _target), do: "Enter the final price for this order before delivery."
  defp discount_help(_, target) when is_binary(target), do: "The amount applies to this entire order line."
  defp discount_help(_, _target), do: "The amount applies to this order before delivery."

  defp normalize_product(product) do
    %{
      id: value(product, :id),
      name: value(product, :name),
      code: value(product, :code),
      date_create: value(product, :date_create),
      image_raw: value(product, :image_raw),
      image_updated_at: product_image_version(product),
      inventory_quantity: value(product, :inventory_quantity),
      price: value(product, :price),
      sub: value(product, :sub),
      tax: value(product, :tax)
    }
  end

  defp normalize_customer(customer) do
    %{
      id: value(customer, :id),
      name: value(customer, :name),
      celphone: value(customer, :celphone),
      address: value(customer, :address),
      document_id: value(customer, :document_id),
      email: value(customer, :email),
      wholesaler: value(customer, :wholesaler),
      is_wholesaler: value(customer, :is_wholesaler)
    }
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp print_request_id, do: "print-#{System.unique_integer([:positive])}"

  defp receipt_payload(sale, store) do
    %{
      id: value(sale, :id),
      sequence: value(sale, :sequence),
      client_name: value(value(sale, :client) || %{}, :name),
      client_document_id: value(value(sale, :client) || %{}, :document_id),
      client_celphone: value(value(sale, :client) || %{}, :celphone),
      login: value(sale, :login),
      sale_type: value(sale, :sale_type),
      amount: value(sale, :amount),
      sub: value(sale, :sub),
      tax_amount: value(sale, :tax_amount),
      discount: value(sale, :discount),
      delivery_charge: value(sale, :delivery_charge),
      additional_info: value(sale, :additional_info),
      date_create: value(sale, :date_create),
      due_date: value(sale, :due_date),
      sequence_type: value(sale, :sequence_type),
      status: value(sale, :status),
      total_paid: value(sale, :total_paid),
      change_amount: value(sale, :change_amount),
      due_balance: value(sale, :due_balance),
      invoice_status: value(sale, :invoice_status),
      store: printable_store(store),
      lines:
        Enum.map(value(sale, :sale_lines) || value(sale, :lines) || [], fn line ->
          %{
            product_id: value(line, :product_id),
            product: %{
              name: value(value(line, :product) || %{}, :name),
              code: value(value(line, :product) || %{}, :code)
            },
            quantity: value(line, :quantity),
            amount: value(line, :amount),
            tax_amount: value(line, :tax_amount),
            discount: value(line, :discount),
            discount_type: value(line, :discount_type),
            discount_input: value(line, :discount_input),
            total_amount: value(line, :total_amount)
          }
        end),
      payments:
        Enum.map(value(sale, :sale_paids) || value(sale, :payments) || [], fn payment ->
          %{
            id: value(payment, :id),
            type: value(payment, :type),
            amount: value(payment, :amount),
            login: value(payment, :login),
            date_create: value(payment, :date_create)
          }
        end)
    }
  end

  defp current_store(socket),
    do: Enum.find(socket.assigns.stores, &(&1.id == socket.assigns.store_id))

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

  defp print_prompt(:receipt, receipt) do
    %{
      title: "Sale completed",
      description: "Would you like to print the receipt?",
      button: "Print receipt",
      event: "printer:print-receipt",
      payload: %{request_id: print_request_id(), receipt: receipt}
    }
  end

  defp update_print_prompt(%{assigns: %{print_prompt: nil}} = socket, _status, _printing),
    do: socket

  defp update_print_prompt(socket, status, printing),
    do: update(socket, :print_prompt, &Map.merge(&1, %{status: status, printing: printing}))

  defp normalize_client_info(params) do
    %{
      user_agent: string_param(params, "user_agent"),
      platform: string_param(params, "platform"),
      mobile: params["mobile"] == true,
      tablet: params["tablet"] == true,
      touch_points: integer_param(params, "touch_points"),
      webusb: params["webusb"] == true
    }
  end

  defp string_param(params, key) when is_map(params) do
    case params[key] do
      value when is_binary(value) -> String.slice(value, 0, 512)
      _ -> nil
    end
  end

  defp integer_param(params, key) when is_map(params) do
    case params[key] do
      value when is_integer(value) -> value
      value when is_binary(value) -> String.to_integer(value)
      _ -> 0
    end
  rescue
    _ -> 0
  end

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
          <h2 id="receipt-dialog-title" class="dialog-title">{@prompt.title}</h2>
          <p id="receipt-print-description" class="dialog-description">{@prompt.description}</p>
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
            No, return to POS
          </button><button
            id="print-receipt"
            class="btn"
            type="button"
            data-variant="default"
            phx-click="confirm_print"
            disabled={@prompt[:printing] == true}
          >{@prompt.button}</button>
        </div>
      </div>
    </dialog>
    """
  end

  defp wholesaler_value(value) when value in [true, 1, "1", "true", "on"], do: 1
  defp wholesaler_value(_), do: 0

  defp selected_store(stores, selected_id) do
    case Integer.parse(to_string(selected_id || "")) do
      {id, ""} -> Enum.find(stores, List.first(stores), &(&1.id == id))
      _ -> List.first(stores)
    end
  end

  defp state(%{assigns: assigns}), do: assigns
  defp state(assigns), do: assigns
  defp sync(socket) do
    socket
    |> assign(:pos_state, Map.drop(socket.assigns, [:pos_state]))
    |> push_event("pos:draft-changed", %{draft: draft_payload(socket.assigns)})
  end
end
