defmodule TigooServer.Retaily.Sales do
  @moduledoc false

  import Ecto.Query
  require Logger

  alias Ecto.Changeset
  alias TigooServer.{InventoryEvents, Repo}
  alias TigooServer.Addons.Events, as: AddonEvents
  alias TigooServer.Accounts.Scope, as: AccessScope

  alias TigooServer.Retaily.{
    Client,
    BusinessTime,
    Inventory,
    PricingList,
    Product,
    ProductTraces,
    Sale,
    SaleLine,
    SalePaid,
    Sequence,
    User,
    UserStore
  }

  alias TigooServer.Retaily.SaleRequests.{Checkout, Payment}

  @tax_rate Decimal.new("0.18")
  @zero Decimal.new(0)

  def create_sale(scope, attrs) do
    with {:ok, checkout} <- valid_checkout(attrs),
         :ok <- delivery_allowed?(scope, checkout),
         {:ok, cashier, tenant} <- cashier(scope) do
      with {:ok, sale} <-
             Repo.transaction(fn ->
               with :ok <- cashier_store?(cashier, checkout.store_id, tenant),
                    %Client{} = client <- Repo.get(Client, checkout.client_id, prefix: tenant),
                    {:ok, sequence} <- next_sequence(checkout.sequence_type, tenant),
                    {:ok, lines} <- sale_lines(checkout.lines, checkout.store_id, tenant),
                    totals <- totals(lines, checkout),
                    :ok <- valid_payments?(checkout.payments, totals.amount),
                    {:ok, sale} <-
                      insert_sale(checkout, cashier.username, sequence, totals, tenant),
                    {:ok, _} <- insert_lines(lines, sale.id, tenant),
                    {:ok, _} <-
                      insert_payments(checkout.payments, sale.id, cashier.username, tenant) do
                 %{
                   sale: sale_response(sale.id, tenant),
                   traces: sale_trace_attrs(lines, sale, checkout, client.name, cashier.username)
                 }
               else
                 nil -> Repo.rollback(:not_found)
                 {:error, reason} -> Repo.rollback(reason)
                 :error -> Repo.rollback(:forbidden_store)
               end
             end) do
        InventoryEvents.broadcast(
          tenant,
          checkout.store_id,
          Enum.map(checkout.lines, & &1.product_id)
        )

        ProductTraces.dispatch(tenant, sale.traces)
        AddonEvents.dispatch(:sale_completed, sale.sale, scope)
        {:ok, sale.sale}
      end
    end
  end

  defp delivery_allowed?(scope, checkout) do
    if Decimal.compare(checkout.delivery_charge || @zero, @zero) == :gt and
         !AccessScope.allowed?(scope, "pos.delivery"),
       do: {:error, :forbidden},
       else: :ok
  end

  def add_payment(scope, sale_id, attrs) do
    with {:ok, payment} <- valid_payment(attrs), {:ok, cashier, tenant} <- cashier(scope) do
      Repo.transaction(fn ->
        with %Sale{} = sale <- locked_sale(sale_id, tenant),
             :ok <- cashier_store?(cashier, sale.store_id, tenant),
             :ok <- open_sale?(sale, tenant),
             :ok <- payment_within_balance?(sale, payment.amount, tenant),
             {:ok, _} <- insert_payments([payment], sale.id, cashier.username, tenant) do
          sale_response(sale.id, tenant)
        else
          nil -> Repo.rollback(:not_found)
          {:error, reason} -> Repo.rollback(reason)
          :error -> Repo.rollback(:forbidden_store)
        end
      end)
    end
  end

  def cancel_sale(scope, sale_id) do
    with {:ok, cashier, tenant} <- cashier(scope) do
      with {:ok, {sale_response, inventory_changed?}} <-
             Repo.transaction(fn ->
               with %Sale{} = sale <- locked_sale(sale_id, tenant),
                    :ok <- cashier_store?(cashier, sale.store_id, tenant) do
                 if sale.status == "RETURN" do
                   {sale_response(sale.id, tenant), false}
                 else
                   lines =
                     Repo.all(
                       from(line in SaleLine, where: line.sale_id == ^sale.id, lock: "FOR UPDATE"),
                       prefix: tenant
                     )

                   Enum.each(lines, fn line -> restore_inventory!(line, sale.store_id, tenant) end)

                   sale
                   |> Changeset.change(status: "RETURN", cancelled_by: cashier.username)
                   |> Repo.update!(prefix: tenant)

                   {sale_response(sale.id, tenant), true}
                 end
               else
                 nil -> Repo.rollback(:not_found)
                 :error -> Repo.rollback(:forbidden_store)
               end
             end) do
        if inventory_changed?,
          do:
            InventoryEvents.broadcast(
              tenant,
              sale_response.store_id,
              Enum.map(sale_response.lines, & &1.product_id)
            )

        {:ok, sale_response}
      end
    end
  end

  def list_sales(scope, filters \\ %{}) do
    with {:ok, cashier, tenant} <- cashier(scope) do
      store_ids = cashier_store_ids(cashier.id, tenant)

      query =
        from(sale in Sale,
          where: sale.store_id in ^store_ids,
          order_by: [desc: sale.id],
          preload: [:client, :sale_paids, sale_lines: :product]
        )
        |> with_payment_totals()
        |> apply_filters(filters)

      {:ok,
       query
       |> Repo.all(prefix: tenant)
       |> Enum.map(&serialize_sale/1)
       |> filter_invoice_status(filters["invoice_status"])}
    end
  end

  @doc "Returns the ten newest purchases for a customer that the cashier can access."
  def recent_customer_purchases(scope, customer_id) do
    with {:ok, cashier, tenant} <- cashier(scope) do
      # Admin scopes are represented by a lightweight session map without an
      # employee record id. `cashier_store_ids/2` deliberately accepts nil for
      # that case and returns every store in the tenant.
      store_ids = cashier_store_ids(Map.get(cashier, :id), tenant)

      purchases =
        from(sale in Sale,
          where: sale.client_id == ^customer_id and sale.store_id in ^store_ids,
          order_by: [desc_nulls_last: sale.date_create, desc: sale.id],
          limit: 10
        )
        |> with_payment_totals()
        |> Repo.all(prefix: tenant)
        |> then(&Repo.preload(&1, [sale_lines: :product], prefix: tenant))
        |> Enum.map(&serialize_purchase(&1, tenant))

      {:ok, purchases}
    end
  end

  def customer_detail(scope, customer_id) do
    with {:ok, cashier, tenant} <- cashier(scope) do
      store_ids = cashier_store_ids(Map.get(cashier, :id), tenant)
      customer = Repo.get(Client, customer_id, prefix: tenant)

      if customer do
        sales =
          from(sale in Sale,
            where:
              sale.client_id == ^customer_id and sale.store_id in ^store_ids and
                sale.status != "RETURN"
          )
          |> with_payment_totals()
          |> Repo.all(prefix: tenant)

        summary =
          Enum.reduce(
            sales,
            %{
              purchase_count: 0,
              total_invoiced: @zero,
              total_paid: @zero,
              pending_balance: @zero,
              last_purchase_date: nil
            },
            fn sale, acc ->
              %{
                acc
                | purchase_count: acc.purchase_count + 1,
                  total_invoiced: Decimal.add(acc.total_invoiced, sale.amount),
                  total_paid: Decimal.add(acc.total_paid, sale.total_paid),
                  pending_balance: Decimal.add(acc.pending_balance, sale.due_balance),
                  last_purchase_date: max_date(acc.last_purchase_date, sale.date_create)
              }
            end
          )

        with {:ok, purchases} <- recent_customer_purchases(scope, customer_id) do
          {:ok,
           %{
             customer:
               serialize_client(customer)
               |> Map.merge(%{date_create: customer.date_create, wholesaler: customer.wholesaler}),
             summary: summary,
             purchases: purchases
           }}
        end
      else
        {:error, :not_found}
      end
    end
  end

  def get_sale(scope, sale_id) do
    with {:ok, cashier, tenant} <- cashier(scope),
         %Sale{} = sale <- Repo.get(Sale, sale_id, prefix: tenant),
         :ok <- cashier_store?(cashier, sale.store_id, tenant) do
      {:ok, sale_response(sale.id, tenant)}
    else
      nil -> {:error, :not_found}
      :error -> {:error, :forbidden_store}
    end
  end

  defp valid_checkout(attrs) do
    changeset = Checkout.changeset(%Checkout{}, attrs)
    if changeset.valid?, do: {:ok, Changeset.apply_changes(changeset)}, else: {:error, changeset}
  end

  defp valid_payment(attrs) do
    changeset = Payment.changeset(%Payment{}, attrs)
    if changeset.valid?, do: {:ok, Changeset.apply_changes(changeset)}, else: {:error, changeset}
  end

  # The authenticated account name is the Retaily cashier username. It is not supplied by the client.
  defp cashier(%AccessScope{actor: :admin, tenant: tenant, login: login}),
    do: {:ok, %{username: login, admin?: true}, tenant}

  defp cashier(%AccessScope{actor: :employee, actor_id: id, tenant: tenant}) do
    case Repo.one(from(user in User, where: user.id == ^id and user.is_active == 1),
           prefix: tenant
         ) do
      nil -> {:error, :cashier_not_found}
      user -> {:ok, user, tenant}
    end
  end

  defp cashier(_), do: {:error, :unauthorized}

  defp cashier_store?(%{admin?: true}, store_id, tenant) do
    if Repo.exists?(from(store in TigooServer.Retaily.Store, where: store.id == ^store_id),
         prefix: tenant
       ),
       do: :ok,
       else: :error
  end

  defp cashier_store?(cashier, store_id, tenant) do
    if Repo.exists?(
         from(link in UserStore,
           where: link.user_id == ^cashier.id and link.store_id == ^store_id
         ),
         prefix: tenant
       ),
       do: :ok,
       else: :error
  end

  defp cashier_store_ids(nil, tenant),
    do: Repo.all(from(store in TigooServer.Retaily.Store, select: store.id), prefix: tenant)

  defp cashier_store_ids(cashier_id, tenant),
    do:
      Repo.all(from(link in UserStore, where: link.user_id == ^cashier_id, select: link.store_id),
        prefix: tenant
      )

  defp next_sequence(code, tenant) do
    case Repo.one(from(sequence in Sequence, where: sequence.code == ^code, lock: "FOR UPDATE"),
           prefix: tenant
         ) do
      nil ->
        {:error, :sequence_not_found}

      sequence ->
        current = sequence.current_seq + sequence.increment_by

        {:ok, updated} =
          Repo.update(Changeset.change(sequence, current_seq: current), prefix: tenant)

        {:ok,
         String.pad_trailing(updated.prefix, updated.fill, "0") <> Integer.to_string(current)}
    end
  end

  defp sale_lines(lines, store_id, tenant) do
    if duplicate_products?(lines) do
      {:error, :duplicate_product_lines}
    else
      Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, result} ->
        inventory =
          Repo.one(
            from(i in Inventory,
              where: i.store_id == ^store_id and i.product_id == ^line.product_id,
              lock: "FOR UPDATE"
            ),
            prefix: tenant
          )

        product = Repo.get(Product, line.product_id, prefix: tenant)
        price = if product, do: sale_price(product, tenant)

        cond do
          is_nil(inventory) or is_nil(product) ->
            {:halt, {:error, :product_not_found}}

          product.active != 1 ->
            {:halt, {:error, :inactive_product}}

          product.archived == "1" ->
            {:halt, {:error, :archived_product}}

          is_nil(price) ->
            {:halt, {:error, :product_has_no_price}}

          true ->
            # Retaily allows backorders, including sales from an already
            # negative inventory balance. The locked row still guarantees
            # this decrement is atomic.
            # Normalize the active catalog price before it becomes the
            # immutable Decimal sale snapshot.
            unit_price = price |> Decimal.from_float() |> Decimal.round(2)
            discount = line_discount(line, unit_price)
            extended = unit_price |> Decimal.mult(line.quantity) |> Decimal.sub(discount)

            if Decimal.negative?(extended) do
              {:halt, {:error, :discount_exceeds_line}}
            else
              before = inventory.quantity || 0

              Repo.update!(
                Changeset.change(inventory,
                  prev_quantity: before,
                  quantity: before - line.quantity,
                  last_update: BusinessTime.local_now(tenant)
                ),
                prefix: tenant
              )

              {:cont,
               {:ok,
                [
                  %{
                    line: line,
                    price: unit_price,
                    discount: discount,
                    total: extended,
                    quantity_before: before,
                    quantity_after: before - line.quantity,
                    unit_cost: product.cost
                  }
                  | result
                ]}}
            end
        end
      end)
    end
  end

  defp insert_sale(checkout, login, sequence, totals, tenant) do
    %Sale{}
    |> Sale.changeset(%{
      amount: totals.amount,
      sub: totals.sub,
      discount: totals.discount,
      discount_type: totals.discount_type,
      discount_input: totals.discount_input,
      tax_amount: totals.tax,
      delivery_charge: checkout.delivery_charge,
      sequence: sequence,
      sequence_type: checkout.sequence_type,
      status: checkout.status,
      sale_type: checkout.sale_type,
      due_date: checkout.due_date,
      login: login,
      client_id: checkout.client_id,
      store_id: checkout.store_id,
      additional_info: checkout.additional_info
    })
    |> Repo.insert(prefix: tenant)
  end

  defp sale_trace_attrs(lines, sale, checkout, customer_name, username) do
    Enum.map(lines, fn %{
                         line: line,
                         price: price,
                         discount: discount,
                         quantity_before: before,
                         quantity_after: quantity_after,
                         unit_cost: cost
                       } ->
      %{
        product_id: line.product_id,
        store_id: checkout.store_id,
        event_type: "sale",
        quantity_before: before,
        quantity_change: -line.quantity,
        quantity_after: quantity_after,
        unit_cost: cost,
        unit_price: Decimal.to_float(price),
        reference_type: "sale",
        reference_id: sale.id,
        operator_username: username,
        customer_id: checkout.client_id,
        customer_name: customer_name,
        metadata: %{
          sale_sequence: sale.sequence,
          discount: discount,
          discount_type: discount_type(line)
        }
      }
    end)
  end

  defp sale_price(product, tenant) do
    pricing_price =
      Repo.one(
        from(entry in PricingList,
          where: entry.product_id == ^product.id and entry.pricing_id == 1,
          order_by: [desc: entry.id],
          select: entry.price,
          limit: 1
        ),
        prefix: tenant
      )

    pricing_price
  end

  defp insert_lines(lines, sale_id, tenant) do
    Enum.reduce_while(lines, {:ok, []}, fn %{
                                             line: line,
                                             price: price,
                                             discount: discount,
                                             total: total
                                           },
                                           {:ok, result} ->
      attrs = %{
        amount: price,
        tax_amount: @zero,
        discount: discount,
        discount_type: discount_type(line),
        discount_input: line.discount_input,
        quantity: line.quantity,
        total_amount: total,
        sale_id: sale_id,
        product_id: line.product_id
      }

      case %SaleLine{} |> SaleLine.changeset(attrs) |> Repo.insert(prefix: tenant) do
        {:ok, inserted} -> {:cont, {:ok, [inserted | result]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp insert_payments(payments, sale_id, login, tenant) do
    Enum.reduce_while(payments, {:ok, []}, fn payment, {:ok, result} ->
      attrs = %{
        amount: payment.amount,
        type: payment.type,
        sale_id: sale_id,
        login: login,
        date_create: BusinessTime.local_now(tenant)
      }

      case %SalePaid{} |> SalePaid.changeset(attrs) |> Repo.insert(prefix: tenant) do
        {:ok, inserted} -> {:cont, {:ok, [inserted | result]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp valid_payments?(payments, amount) do
    total = Enum.reduce(payments, @zero, &Decimal.add(&1.amount, &2))

    if Decimal.compare(total, amount) in [:lt, :eq] do
      :ok
    else
      Logger.warning("payment_exceeds_balance: recording payment above sale total")
      :ok
    end
  end

  defp totals(lines, checkout) do
    merchandise = Enum.reduce(lines, @zero, &Decimal.add(&1.total, &2))
    global_discount = sale_discount(checkout, merchandise)
    line_discount = Enum.reduce(lines, @zero, &Decimal.add(&1.discount, &2))
    discount = Decimal.add(line_discount, global_discount)
    taxable = Decimal.sub(merchandise, global_discount)
    sub = Decimal.div(taxable, Decimal.add(Decimal.new(1), @tax_rate)) |> Decimal.round(2)
    tax = Decimal.sub(taxable, sub)

    %{
      amount: Decimal.add(taxable, checkout.delivery_charge),
      sub: sub,
      tax: tax,
      discount: discount,
      discount_type: discount_type(checkout),
      discount_input: checkout.discount_input
    }
  end

  defp line_discount(line, unit_price) do
    gross = Decimal.mult(unit_price, line.quantity)

    case discount_type(line) do
      "percentage" ->
        gross |> Decimal.mult(line.discount_input) |> Decimal.div(100) |> Decimal.round(2)

      _ ->
        line.discount
    end
  end

  defp sale_discount(checkout, merchandise) do
    discount =
      case discount_type(checkout) do
        "percentage" ->
          merchandise
          |> Decimal.mult(checkout.discount_input)
          |> Decimal.div(100)
          |> Decimal.round(2)

        _ ->
          checkout.discount
      end

    if Decimal.compare(discount, merchandise) == :gt, do: merchandise, else: discount
  end

  defp discount_type(%{discount: discount, discount_type: type}) do
    if Decimal.positive?(discount), do: type || "money", else: nil
  end

  defp locked_sale(id, tenant),
    do: Repo.one(from(sale in Sale, where: sale.id == ^id, lock: "FOR UPDATE"), prefix: tenant)

  defp open_sale?(%Sale{status: "RETURN"}, _tenant), do: {:error, :cancelled_sale}

  defp open_sale?(sale, tenant),
    do:
      if(Decimal.compare(payment_total(sale.id, tenant), sale.amount) == :lt,
        do: :ok,
        else: {:error, :sale_paid}
      )

  defp payment_within_balance?(sale, amount, tenant) do
    due = Decimal.sub(sale.amount, payment_total(sale.id, tenant))

    if Decimal.compare(amount, due) in [:lt, :eq],
      do: :ok,
      else: {:error, :payment_exceeds_balance}
  end

  defp payment_total(sale_id, tenant) do
    Repo.one(
      from(payment in SalePaid,
        where: payment.sale_id == ^sale_id,
        select: coalesce(sum(payment.amount), ^@zero)
      ),
      prefix: tenant
    )
  end

  defp outstanding_balance(amount, paid) do
    if Decimal.positive?(Decimal.sub(amount, paid)), do: Decimal.sub(amount, paid), else: @zero
  end

  defp restore_inventory!(line, store_id, tenant) do
    inventory =
      Repo.one!(
        from(i in Inventory,
          where: i.store_id == ^store_id and i.product_id == ^line.product_id,
          lock: "FOR UPDATE"
        ),
        prefix: tenant
      )

    quantity = trunc(line.quantity)

    Repo.update!(
      Changeset.change(inventory,
        prev_quantity: inventory.quantity,
        quantity: inventory.quantity + quantity,
        last_update: BusinessTime.local_now(tenant)
      ),
      prefix: tenant
    )
  end

  defp sale_response(id, tenant) do
    sale =
      from(sale in Sale, where: sale.id == ^id)
      |> with_payment_totals()
      |> Repo.one!(prefix: tenant)
      |> Repo.preload([:client, :sale_paids, sale_lines: sale_lines_with_price_query()], prefix: tenant)

    sale
    |> serialize_sale()
    |> Map.put(:salesperson, serialize_salesperson(sale.login, tenant))
  end

  defp serialize_sale(sale) do
    paid = sale.total_paid || Enum.reduce(sale.sale_paids, @zero, &Decimal.add(&1.amount, &2))
    # An overpayment is cash returned as change, never a negative invoice balance.
    due = sale.due_balance || outstanding_balance(sale.amount, paid)

    change =
      if Decimal.positive?(Decimal.sub(paid, sale.amount)),
        do: Decimal.sub(paid, sale.amount),
        else: @zero

    invoice_status =
      sale.invoice_status ||
        if(sale.status == "RETURN",
          do: "cancelled",
          else: if(Decimal.positive?(due), do: "open", else: "close")
        )

    %{
      id: sale.id,
      amount: sale.amount,
      sub: sale.sub,
      discount: sale.discount,
      discount_type: sale.discount_type,
      discount_input: sale.discount_input,
      global_discount: global_discount(sale),
      tax_amount: sale.tax_amount,
      delivery_charge: sale.delivery_charge,
      sequence: sale.sequence,
      sequence_type: sale.sequence_type,
      status: sale.status,
      sale_type: sale.sale_type,
      date_create: sale.date_create,
      due_date: sale.due_date,
      store_id: sale.store_id,
      login: sale.login,
      cancelled_by: sale.cancelled_by,
      additional_info: sale.additional_info,
      client: serialize_client(sale.client),
      lines: Enum.map(sale.sale_lines, &serialize_line/1),
      # Stable chronological ordering makes each payment's running balance
      # deterministic for the payment receipt without changing sale data.
      payments:
        sale.sale_paids
        |> Enum.sort_by(&{&1.date_create, &1.id})
        |> Enum.map(&serialize_payment/1),
      total_paid: paid,
      change_amount: change,
      due_balance: due,
      invoice_status: invoice_status
    }
  end

  defp serialize_purchase(sale, tenant) do
    %{
      id: sale.id,
      sequence: sale.sequence,
      amount: sale.amount,
      total_paid: sale.total_paid,
      due_balance: sale.due_balance,
      date_create: sale.date_create,
      due_date: sale.due_date,
      store_id: sale.store_id,
      status: sale.status,
      invoice_status: sale.invoice_status,
      salesperson: sale.login,
      memo_author: serialize_salesperson(sale.login, tenant),
      additional_info: sale.additional_info,
      items: Enum.map(sale.sale_lines, &serialize_purchase_item/1)
    }
  end

  defp max_date(nil, date), do: date
  defp max_date(date, nil), do: date

  defp max_date(left, right),
    do: if(NaiveDateTime.compare(left, right) == :lt, do: right, else: left)

  defp serialize_purchase_item(line) do
    %{
      product_id: line.product_id,
      name: line.product.name,
      quantity: line.quantity,
      price: line.amount,
      discount: line.discount,
      discount_type: line.discount_type,
      discount_input: line.discount_input,
      total: line.total_amount
    }
  end

  defp serialize_client(client) do
    %{
      id: client.id,
      name: client.name,
      document_id: client.document_id,
      address: client.address,
      celphone: client.celphone,
      email: client.email
    }
  end

  defp serialize_line(line) do
    price = line.price || line.amount
    line_price = line_price(line)

    %{
      id: line.id,
      amount: line.amount,
      tax_amount: line.tax_amount,
      discount: line.discount,
      discount_type: line.discount_type,
      discount_input: line.discount_input,
      quantity: line.quantity,
      price: price,
      line_price: line_price,
      invoice_total: Decimal.sub(line_price, line.discount || @zero),
      total_amount: line.total_amount,
      product_id: line.product_id,
      product: %{
        id: line.product.id,
        name: line.product.name,
        price: line.amount,
        code: line.product.code,
        active: line.product.active
      }
    }
  end

  defp sale_lines_with_price_query do
    latest_prices =
      from(price in PricingList,
        join: latest in subquery(
          from(price in PricingList,
            where: price.pricing_id == 1,
            group_by: price.product_id,
            select: %{product_id: price.product_id, id: max(price.id)}
          )
        ),
        on: latest.id == price.id,
        select: %{product_id: price.product_id, price: price.price}
      )

    from(line in SaleLine,
      left_join: price in subquery(latest_prices),
      on: price.product_id == line.product_id,
      preload: [:product],
      select_merge: %{price: type(fragment("?::numeric", price.price), :decimal)}
    )
  end

  defp line_price(line) do
    (line.price || line.amount || @zero)
    |> Decimal.mult(Decimal.from_float(line.quantity || 0.0))
    |> Decimal.round(2)
  end

  defp global_discount(sale) do
    line_discount = Enum.reduce(sale.sale_lines, @zero, &Decimal.add(&1.discount, &2))
    Decimal.sub(sale.discount, line_discount)
  end

  defp serialize_payment(payment) do
    %{
      id: payment.id,
      amount: payment.amount,
      type: payment.type,
      login: payment.login,
      date_create: payment.date_create
    }
  end

  defp serialize_salesperson(login, tenant) do
    case Repo.one(
           from(user in User,
             where: user.username == ^login,
             select: %{
               first_name: user.first_name,
               last_name: user.last_name,
               username: user.username,
               pic: user.pic
             }
           ),
           prefix: tenant
         ) do
      nil ->
        nil

      user ->
        %{
          name: [user.first_name, user.last_name] |> Enum.reject(&is_nil/1) |> Enum.join(" "),
          username: user.username,
          pic: user.pic
        }
    end
  end

  defp apply_filters(query, filters) do
    query
    |> maybe_where(:store_id, filters["store_id"])
    |> maybe_where(:client_id, filters["client_id"])
    |> maybe_where(:login, filters["cashier"])
    |> maybe_date(:date_from, filters["date_from"], :gte)
    |> maybe_date(:date_to, filters["date_to"], :lte)
  end

  # Totals and invoice status are projected by PostgreSQL, avoiding per-sale payment queries.
  defp with_payment_totals(query) do
    totals =
      from(payment in SalePaid,
        group_by: payment.sale_id,
        select: %{sale_id: payment.sale_id, total_paid: sum(payment.amount)}
      )

    from(sale in query,
      left_join: payment_total in subquery(totals),
      on: payment_total.sale_id == sale.id,
      select_merge: %{
        total_paid: coalesce(payment_total.total_paid, ^@zero),
        due_balance:
          fragment(
            "CASE WHEN ? = 'RETURN' THEN ? ELSE GREATEST(? - COALESCE(?, ?), ?) END",
            sale.status,
            ^@zero,
            sale.amount,
            payment_total.total_paid,
            ^@zero,
            ^@zero
          ),
        invoice_status:
          fragment(
            "CASE WHEN ? = 'RETURN' THEN 'cancelled' WHEN ? - COALESCE(?, ?) > 0 THEN 'open' ELSE 'close' END",
            sale.status,
            sale.amount,
            payment_total.total_paid,
            ^@zero
          )
      }
    )
  end

  defp maybe_where(query, _field, nil), do: query

  defp maybe_where(query, field, value) when field in [:store_id, :client_id] do
    from(sale in query, where: field(sale, ^field) == ^value)
  end

  defp maybe_where(query, :login, value) do
    from(sale in query, where: sale.login == ^value)
  end

  defp maybe_date(query, _field, nil, _operator), do: query

  defp maybe_date(query, :date_from, value, :gte) do
    from(sale in query, where: sale.date_create >= ^value)
  end

  defp maybe_date(query, :date_to, value, :lte) do
    from(sale in query, where: sale.date_create <= ^value)
  end

  defp filter_invoice_status(sales, nil), do: sales
  defp filter_invoice_status(sales, "all"), do: sales

  defp filter_invoice_status(sales, status),
    do: Enum.filter(sales, &(&1.invoice_status == status))

  defp duplicate_products?(lines),
    do: lines |> Enum.map(& &1.product_id) |> Enum.uniq() |> length() != length(lines)
end
