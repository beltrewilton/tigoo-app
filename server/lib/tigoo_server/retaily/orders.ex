defmodule TigooServer.Retaily.Orders do
  @moduledoc false

  import Ecto.Query

  alias Ecto.Changeset
  alias TigooServer.{InventoryEvents, Repo}
  alias TigooServer.Accounts.Scope, as: AccessScope
  alias TigooServer.Retaily.OrderRequests.{Create, Receive}

  alias TigooServer.Retaily.{
    Inventory,
    InventoryContext,
    BusinessTime,
    Product,
    ProductOrder,
    ProductOrderLine,
    ProductTraces,
    Provider,
    Store,
    User,
    UserStore
  }

  def create_order(scope, attrs) do
    with {:ok, request} <- valid(Create, attrs),
         {:ok, cashier, tenant} <- cashier(scope),
         :ok <- cashier_store?(cashier, request.to_store_id, tenant) do
      Repo.transaction(fn ->
        with %Store{} <- Repo.get(Store, request.to_store_id, prefix: tenant),
             :ok <- products_exist?(request.lines, tenant),
             {:ok, order} <- insert_order(request, cashier.username, tenant),
             {:ok, _lines} <- insert_lines(request.lines, order, tenant) do
          order_response(order.id, tenant)
        else
          nil -> Repo.rollback(:not_found)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      :error -> {:error, :forbidden_store}
      {:error, _reason} = error -> error
    end
  end

  def list_orders(scope, store_id, status \\ nil) do
    with {:ok, cashier, tenant} <- cashier(scope),
         :ok <- cashier_store?(cashier, store_id, tenant) do
      base_query = from(order in ProductOrder, where: order.to_store_id == ^store_id)

      orders =
        base_query
        |> maybe_filter_status(status)
        |> order_by([order], desc: order.date_closed, desc: order.date_opened)
        |> preload([order], lines: :product)
        |> Repo.all(prefix: tenant)

      status_counts =
        Repo.all(
          from(order in base_query,
            group_by: order.status,
            select: {order.status, count(order.id)}
          ),
          prefix: tenant
        )
        |> Map.new()

      store_names = store_names(orders, tenant)
      provider_names = provider_names(orders, tenant)

      {:ok,
       %{
         entries: Enum.map(orders, &serialize_order(&1, store_names, provider_names, tenant)),
         status_counts: status_counts
       }}
    else
      :error -> {:error, :forbidden_store}
      {:error, _} = error -> error
    end
  end

  def list_purchase_sources(scope, store_id) do
    with {:ok, tenant} <- InventoryContext.authorize_store(scope, store_id) do
      providers =
        Repo.all(
          from(provider in Provider,
            order_by: [asc: provider.name],
            select: %{id: provider.id, name: provider.name}
          ),
          prefix: tenant
        )

      {:ok, providers}
    end
  end

  def receive_order(scope, order_id, attrs) do
    with {:ok, receipt} <- valid(Receive, attrs),
         {:ok, cashier, tenant} <- cashier(scope),
         {:ok, order} <-
           Repo.transaction(fn ->
             with %ProductOrder{} = order <- locked_order(order_id, tenant),
                  :ok <- cashier_store?(cashier, order.to_store_id, tenant),
                  :ok <- order_open?(order),
                  lines <- locked_lines(order.id, tenant),
                  :ok <- valid_receipt_lines?(receipt.lines, lines),
                  {:ok, traces} <-
                    receive_lines(lines, receipt, cashier.username, order.from_origin_id, tenant),
                  {:ok, _} <- close_order(order, cashier.username, tenant) do
               %{order: order_response(order.id, tenant), traces: traces}
             else
               nil -> Repo.rollback(:not_found)
               :error -> Repo.rollback(:forbidden_store)
               {:error, reason} -> Repo.rollback(reason)
             end
           end) do
      InventoryEvents.broadcast(
        tenant,
        order.order.to_store_id,
        Enum.map(order.order.lines, & &1.product_id)
      )

      ProductTraces.dispatch(tenant, order.traces)
      {:ok, order.order}
    else
      :error -> {:error, :forbidden_store}
      {:error, _reason} = error -> error
    end
  end

  def adjust_inventory(scope, attrs) do
    with {:ok, product_id} <- positive_integer(attrs["product_id"]),
         {:ok, store_id} <- positive_integer(attrs["store_id"]),
         {:ok, quantity} <- integer(attrs["quantity"]),
         {:ok, cashier, tenant} <- cashier(scope),
         :ok <- cashier_store?(cashier, store_id, tenant),
         {:ok, %{inventory: inventory, trace: trace}} <-
           Repo.transaction(fn ->
             with %Product{} <- Repo.get(Product, product_id, prefix: tenant),
                  %Inventory{} = inventory <- locked_inventory(product_id, store_id, tenant) do
               updated = update_inventory!(inventory, quantity, cashier.username, tenant)

               %{
                 inventory: updated,
                 trace:
                   trace_attrs(inventory, quantity, "inventory_adjustment", cashier.username, %{
                     reference_type: "inventory"
                   })
               }
             else
               nil -> Repo.rollback(:not_found)
             end
           end) do
      InventoryEvents.broadcast(tenant, store_id, [product_id])
      ProductTraces.dispatch(tenant, [trace])
      {:ok, inventory}
    else
      :error -> {:error, :forbidden_store}
      {:error, _reason} = error -> error
    end
  end

  def move_inventory(scope, attrs) do
    attrs = Map.put(attrs, "order_type", "move")

    with {:ok, request} <- valid(Create, attrs),
         false <- request.from_origin_id == request.to_store_id,
         {:ok, cashier, tenant} <- cashier(scope),
         :ok <- cashier_store?(cashier, request.from_origin_id, tenant),
         :ok <- cashier_store?(cashier, request.to_store_id, tenant),
         {:ok, result} <-
           Repo.transaction(fn ->
             with %Store{} <- Repo.get(Store, request.from_origin_id, prefix: tenant),
                  %Store{} <- Repo.get(Store, request.to_store_id, prefix: tenant),
                  :ok <- products_exist?(request.lines, tenant),
                  {:ok, traces} <-
                    move_lines(
                      request.lines,
                      request.from_origin_id,
                      request.to_store_id,
                      cashier.username,
                      tenant
                    ) do
               %{
                 product_ids: request.lines |> Enum.map(& &1.product_id) |> Enum.uniq(),
                 traces: traces
               }
             else
               nil -> Repo.rollback(:not_found)
               {:error, reason} -> Repo.rollback(reason)
             end
           end) do
      InventoryEvents.broadcast(tenant, request.from_origin_id, result.product_ids)
      InventoryEvents.broadcast(tenant, request.to_store_id, result.product_ids)
      ProductTraces.dispatch(tenant, result.traces)
      {:ok, result}
    else
      true -> {:error, :same_store}
      :error -> {:error, :forbidden_store}
      {:error, _reason} = error -> error
    end
  end

  defp valid(module, attrs) do
    changeset = module.changeset(struct(module), attrs)
    if changeset.valid?, do: {:ok, Changeset.apply_changes(changeset)}, else: {:error, changeset}
  end

  defp insert_order(request, username, tenant) do
    %ProductOrder{}
    |> ProductOrder.changeset(%{
      name: request.name,
      memo: request.memo,
      order_type: request.order_type,
      from_origin_id: request.from_origin_id,
      to_store_id: request.to_store_id,
      user_requester: username,
      date_opened: now(tenant),
      status: "opened"
    })
    |> Repo.insert(prefix: tenant)
  end

  defp insert_lines(lines, order, tenant) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, result} ->
      attrs = %{
        product_id: line.product_id,
        from_origin_id: line.from_origin_id || order.from_origin_id,
        to_store_id: order.to_store_id,
        product_order_id: order.id,
        quantity: line.quantity,
        date_create: now(tenant),
        status: "pending"
      }

      case %ProductOrderLine{}
           |> ProductOrderLine.changeset(attrs)
           |> Repo.insert(prefix: tenant) do
        {:ok, inserted} -> {:cont, {:ok, [inserted | result]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp receive_lines(lines, receipt, username, provider_id, tenant) do
    by_id = Map.new(receipt.lines, &{&1.id, &1})

    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, traces} ->
      supplied = Map.get(by_id, line.id)

      observed =
        if supplied && !is_nil(supplied.quantity_observed),
          do: supplied.quantity_observed,
          else: line.quantity

      memo =
        if supplied,
          do: supplied.receiver_memo || receipt.receiver_memo,
          else: receipt.receiver_memo

      with %Inventory{} = inventory <-
             locked_inventory(line.product_id, line.to_store_id, tenant),
           {:ok, _} <- update_received_line(line, observed, memo, username, tenant) do
        update_inventory!(inventory, observed, username, tenant)

        attrs =
          trace_attrs(inventory, observed, "purchase", username, %{
            reference_type: "product_order",
            reference_id: line.product_order_id,
            unit_cost: product_cost(line.product_id, tenant),
            metadata: %{receiver_memo: memo, provider_name: provider_name(provider_id, tenant)}
          })

        {:cont, {:ok, [attrs | traces]}}
      else
        nil -> {:halt, {:error, :inventory_not_found}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp move_lines(lines, from_store_id, to_store_id, username, tenant) do
    transfer_id = System.unique_integer([:positive])

    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, traces} ->
      with %Inventory{} = origin <- locked_inventory(line.product_id, from_store_id, tenant),
           %Inventory{} = destination <- locked_inventory(line.product_id, to_store_id, tenant),
           true <- (origin.quantity || 0) >= line.quantity do
        update_inventory!(origin, -line.quantity, username, tenant)
        update_inventory!(destination, line.quantity, username, tenant)

        common = %{
          reference_type: "store_transfer",
          reference_id: transfer_id,
          source_store_id: from_store_id,
          destination_store_id: to_store_id
        }

        out = trace_attrs(origin, -line.quantity, "store_transfer_out", username, common)
        incoming = trace_attrs(destination, line.quantity, "store_transfer_in", username, common)
        {:cont, {:ok, [incoming, out | traces]}}
      else
        nil -> {:halt, {:error, :not_found}}
        false -> {:halt, {:error, :insufficient_inventory}}
      end
    end)
  end

  defp update_received_line(line, observed, memo, username, tenant) do
    line
    |> ProductOrderLine.changeset(%{
      quantity_observed: observed,
      # The imported Retaily schema limits this column to varchar(10).
      status: "transfered",
      user_receiver: username,
      receiver_last_update: now(tenant),
      receiver_memo: memo
    })
    |> Repo.update(prefix: tenant)
  end

  defp close_order(order, username, tenant) do
    status =
      if Repo.exists?(
           from(line in ProductOrderLine,
             where: line.product_order_id == ^order.id and line.status != "transfered"
           ),
           prefix: tenant
         ),
         do: "received",
         else: "closed"

    order
    |> ProductOrder.changeset(%{status: status, user_receiver: username, date_closed: now(tenant)})
    |> Repo.update(prefix: tenant)
  end

  defp update_inventory!(inventory, delta, username, tenant) do
    previous = inventory.quantity || 0

    inventory
    |> Inventory.changeset(%{
      prev_quantity: previous,
      quantity: previous + delta,
      last_update: now(tenant),
      user_updated: username
    })
    |> Repo.update!(prefix: tenant)
  end

  defp product_cost(product_id, tenant),
    do:
      Repo.one(from(product in Product, where: product.id == ^product_id, select: product.cost),
        prefix: tenant
      )

  defp provider_name(id, tenant),
    do:
      Repo.one(from(provider in Provider, where: provider.id == ^id, select: provider.name),
        prefix: tenant
      )

  defp trace_attrs(inventory, delta, event_type, username, extra) do
    Map.merge(
      %{
        product_id: inventory.product_id,
        store_id: inventory.store_id,
        event_type: event_type,
        quantity_before: inventory.quantity || 0,
        quantity_change: delta,
        quantity_after: (inventory.quantity || 0) + delta,
        operator_username: username
      },
      extra
    )
  end

  defp products_exist?(lines, tenant) do
    ids = lines |> Enum.map(& &1.product_id) |> Enum.uniq()

    count =
      Repo.aggregate(from(product in Product, where: product.id in ^ids), :count, prefix: tenant)

    if count == length(ids), do: :ok, else: {:error, :product_not_found}
  end

  defp valid_receipt_lines?(receipt_lines, lines) do
    ids = MapSet.new(Enum.map(lines, & &1.id))
    supplied = Enum.map(receipt_lines, & &1.id)

    if length(supplied) == MapSet.size(MapSet.new(supplied)) and
         Enum.all?(supplied, &MapSet.member?(ids, &1)) do
      :ok
    else
      {:error, :invalid_receipt_lines}
    end
  end

  defp order_open?(%ProductOrder{status: "opened"}), do: :ok
  defp order_open?(_), do: {:error, :order_already_received}

  defp locked_order(id, tenant),
    do:
      Repo.one(from(order in ProductOrder, where: order.id == ^id, lock: "FOR UPDATE"),
        prefix: tenant
      )

  defp locked_lines(order_id, tenant),
    do:
      Repo.all(
        from(line in ProductOrderLine,
          where: line.product_order_id == ^order_id,
          order_by: [asc: line.id],
          lock: "FOR UPDATE"
        ),
        prefix: tenant
      )

  defp locked_inventory(product_id, store_id, tenant),
    do:
      Repo.one(
        from(inventory in Inventory,
          where: inventory.product_id == ^product_id and inventory.store_id == ^store_id,
          lock: "FOR UPDATE"
        ),
        prefix: tenant
      )

  defp order_response(id, tenant) do
    order =
      Repo.one!(from(order in ProductOrder, where: order.id == ^id, preload: [lines: :product]),
        prefix: tenant
      )

    serialize_order(order, store_names([order], tenant), provider_names([order], tenant), tenant)
  end

  defp serialize_order(order, store_names, provider_names, tenant) do
    current_quantities = current_quantities(order.lines, order.to_store_id, tenant)

    %{
      id: order.id,
      name: order.name,
      memo: order.memo,
      order_type: order.order_type,
      from_origin_id: order.from_origin_id,
      from_origin_name: source_name(order, store_names, provider_names),
      to_store_id: order.to_store_id,
      to_store_name: Map.get(store_names, order.to_store_id, "Unknown store"),
      user_requester: order.user_requester,
      user_receiver: order.user_receiver,
      date_opened: order.date_opened,
      date_closed: order.date_closed,
      status: order.status,
      lines: Enum.map(order.lines, &serialize_line(&1, current_quantities))
    }
  end

  defp store_names(orders, tenant) do
    store_ids =
      orders
      |> Enum.flat_map(&[&1.from_origin_id, &1.to_store_id])
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    Repo.all(from(store in Store, where: store.id in ^store_ids, select: {store.id, store.name}),
      prefix: tenant
    )
    |> Map.new()
  end

  defp provider_names(orders, tenant) do
    provider_ids =
      orders
      |> Enum.filter(&(&1.order_type == "purchase"))
      |> Enum.map(& &1.from_origin_id)
      |> Enum.filter(&is_integer/1)
      |> Enum.uniq()

    Repo.all(
      from(provider in Provider,
        where: provider.id in ^provider_ids,
        select: {provider.id, provider.name}
      ),
      prefix: tenant
    )
    |> Map.new()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [order], order.status == ^status)

  defp source_name(%{order_type: "purchase", from_origin_id: id}, _store_names, provider_names),
    do: Map.get(provider_names, id, "External source")

  defp source_name(order, store_names, _provider_names),
    do: Map.get(store_names, order.from_origin_id, "External source")

  defp current_quantities(lines, store_id, tenant) do
    product_ids = lines |> Enum.map(& &1.product_id) |> Enum.uniq()

    Repo.all(
      from(inventory in Inventory,
        where: inventory.store_id == ^store_id and inventory.product_id in ^product_ids,
        select: {inventory.product_id, inventory.quantity}
      ),
      prefix: tenant
    )
    |> Map.new()
  end

  defp serialize_line(line, current_quantities) do
    %{
      id: line.id,
      product_id: line.product_id,
      product_name: line.product.name,
      product_code: line.product.code,
      product_cost: line.product.cost,
      current_quantity: Map.get(current_quantities, line.product_id, 0),
      from_origin_id: line.from_origin_id,
      to_store_id: line.to_store_id,
      quantity: line.quantity,
      quantity_observed: line.quantity_observed,
      status: line.status,
      user_receiver: line.user_receiver,
      receiver_last_update: line.receiver_last_update,
      receiver_memo: line.receiver_memo
    }
  end

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
    if Repo.exists?(from(store in Store, where: store.id == ^store_id), prefix: tenant),
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

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> {:ok, number}
      _ -> {:error, :invalid_params}
    end
  end

  defp positive_integer(_), do: {:error, :invalid_params}
  defp integer(value) when is_integer(value), do: {:ok, value}

  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, :invalid_params}
    end
  end

  defp integer(_), do: {:error, :invalid_params}
  defp now(tenant), do: BusinessTime.local_now(tenant)
end
