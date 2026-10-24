defmodule TigooServer.Retaily.InventoryContext do
  @moduledoc false

  import Ecto.Query

  alias TigooServer.Repo
  alias TigooServer.Accounts.Scope, as: AccessScope
  alias TigooServer.Retaily.{Inventory, PricingList, Product, Store, User, UserStore}
  alias TigooServer.Retaily.ProductTraces

  def list(scope, store_id, inventory_filter \\ nil, opts \\ []) do
    with {:ok, tenant} <- authorize_store(scope, store_id) do
      include_archived? = Keyword.get(opts, :include_archived?, false)

      entries =
        from(inventory in Inventory,
          join: product in Product,
          on: product.id == inventory.product_id,
          join: store in Store,
          on: store.id == inventory.store_id,
          left_join: price in subquery(default_prices_query()),
          on: price.product_id == product.id,
          left_join: totals in subquery(total_quantities_query()),
          on: totals.product_id == product.id,
          where: inventory.store_id == ^store_id,
          where: ^include_archived? or fragment("COALESCE(?, '0') != '1'", product.archived),
          order_by: [asc: product.name],
          select: %{
            id: inventory.id,
            product_id: inventory.product_id,
            product_name: product.name,
            product_code: product.code,
            product_active: product.active,
            product_archived: product.archived,
            product_cost: product.cost,
            product_price: price.price,
            total_quantity: totals.quantity,
            store_id: inventory.store_id,
            store_name: store.name,
            quantity: inventory.quantity,
            prev_quantity: inventory.prev_quantity,
            last_update: inventory.last_update,
            user_updated: inventory.user_updated
          }
        )
        |> apply_inventory_filter(inventory_filter)
        |> Repo.all(prefix: tenant)

      {:ok, entries}
    end
  end

  def quantities(scope, store_id, product_ids) do
    with {:ok, tenant} <- authorize_store(scope, store_id) do
      entries =
        from(inventory in Inventory,
          where: inventory.store_id == ^store_id and inventory.product_id in ^product_ids,
          select: %{product_id: inventory.product_id, quantity: inventory.quantity}
        )
        |> Repo.all(prefix: tenant)

      {:ok, entries}
    end
  end

  def product_store_quantities(scope, store_id, product_id) do
    with {:ok, tenant} <- authorize_store(scope, store_id) do
      query =
        from(inventory in Inventory,
          join: store in Store,
          on: store.id == inventory.store_id,
          where: inventory.product_id == ^product_id,
          order_by: [asc: store.name],
          select: %{
            id: inventory.id,
            product_id: inventory.product_id,
            store_id: inventory.store_id,
            store_name: store.name,
            quantity: inventory.quantity,
            prev_quantity: inventory.prev_quantity,
            last_update: inventory.last_update,
            user_updated: inventory.user_updated
          }
        )

      query =
        if AccessScope.admin?(scope) do
          query
        else
          where(query, [inventory, _store], inventory.store_id in ^scope.store_ids)
        end

      {:ok,
       Repo.all(query, prefix: tenant)}
    end
  end

  def product_traces(scope, store_id, product_id),
    do: ProductTraces.list(scope, store_id, product_id)

  def stores(%AccessScope{} = scope) do
    query =
      from(store in Store,
        order_by: [asc: store.name],
        select: %{
          id: store.id,
          name: store.name,
          address: store.address,
          slogan: store.slogan,
          logo: store.logo,
          company_id: store.company_id
        }
      )

    query =
      if AccessScope.admin?(scope) do
        query
      else
        where(query, [store], store.id in ^scope.store_ids)
      end

    {:ok, Repo.all(query, prefix: scope.tenant)}
  end

  def authorize_store(scope, store_id) do
    with {:ok, cashier, tenant} <- cashier(scope),
         :ok <- cashier_store?(cashier, store_id, tenant) do
      {:ok, tenant}
    end
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

  defp apply_inventory_filter(query, "negative"),
    do: where(query, [inventory, _product, _store], inventory.quantity < 0)

  defp apply_inventory_filter(query, "uncosted"),
    do:
      where(
        query,
        [inventory, product, _store],
        inventory.quantity > 0 and (is_nil(product.cost) or product.cost <= ^0.0)
      )

  defp apply_inventory_filter(query, _), do: query

  # Pricing id 1 is the existing application default. Keeping this lookup here
  # makes inventory price presentation independent from product.cost and legacy product.price.
  defp default_prices_query do
    from(entry in PricingList,
      where: entry.pricing_id == 1,
      distinct: entry.product_id,
      order_by: [asc: entry.product_id, desc: entry.id],
      select: %{product_id: entry.product_id, price: entry.price}
    )
  end

  defp total_quantities_query do
    from(inventory in Inventory,
      group_by: inventory.product_id,
      select: %{
        product_id: inventory.product_id,
        quantity: fragment("sum(GREATEST(?, 0))", inventory.quantity)
      }
    )
  end
end
