defmodule TigooServer.Retaily.ProductCatalog do
  @moduledoc false

  import Ecto.Query

  alias TigooServer.{InventoryEvents, Repo}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.{BusinessTime, Inventory, Pricing, PricingList, Product, Store}

  def pricing_lists(%Scope{tenant: tenant}) do
    Repo.all(
      from(pricing in Pricing,
        where: pricing.status == 1,
        order_by: [asc: pricing.label],
        select: %{id: pricing.id, label: pricing.label}
      ),
      prefix: tenant
    )
  end

  def create(scope, attrs) do
    with true <- Scope.allowed?(scope, "product.add"),
         store_id when is_integer(store_id) and store_id > 0 <- attrs.store_id,
         {:ok, tenant} <- TigooServer.Retaily.InventoryContext.authorize_store(scope, store_id),
         :ok <- default_price?(attrs.prices) do
      now = BusinessTime.local_now(tenant)
      username = scope.login || get_in(scope.user || %{}, [:name]) || "system"

      result =
        Repo.transaction(fn ->
          product_attrs = %{
            name: attrs.name,
            code: attrs.code,
            cost: attrs.cost,
            image_raw: attrs.image_raw,
            image_updated_at: new_image_timestamp(attrs.image_raw, now),
            active: status_flag(Map.get(attrs, :active, true)),
            user_modified: username,
            date_create: now,
            archived: archived_flag(attrs.archived)
          }

          store_ids = store_ids(tenant)

          with {:ok, product} <-
                 %Product{} |> Product.changeset(product_attrs) |> Repo.insert(prefix: tenant),
               {_, _} <- initialize_inventory(product.id, username, BusinessTime.local_now(tenant), tenant, store_ids),
               :ok <- save_prices(attrs.prices, product.id, username, now, tenant) do
            {product, store_ids}
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      case result do
        {:ok, {product, store_ids}} ->
          InventoryEvents.broadcast_many(tenant, store_ids, [product.id])
          {:ok, product}

        error ->
          error
      end
    else
      false -> {:error, :forbidden}
      _ -> {:error, :invalid_product}
    end
  end

  def get(%Scope{tenant: tenant} = scope, product_id) do
    with true <- can_open_product?(scope),
         %Product{} = product <- Repo.get(Product, product_id, prefix: tenant) do
      prices =
        Repo.all(
          from(entry in PricingList,
            where: entry.product_id == ^product.id,
            select: %{pricing_id: entry.pricing_id, price: entry.price}
          ),
          prefix: tenant
        )

      {:ok,
       %{
         id: product.id,
         name: product.name,
         code: product.code,
         cost: permitted_cost(scope, product.cost),
         image_raw: product.image_raw,
         image_updated_at: product.image_updated_at,
         active: product.active,
         archived: product.archived,
         prices: prices
       }}
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
    end
  end

  def update(%Scope{tenant: tenant} = scope, product_id, attrs) do
    with true <- Scope.allowed?(scope, "product.edit"),
         %Product{} = product <- Repo.get(Product, product_id, prefix: tenant),
         :ok <- default_price?(attrs.prices) do
      username = scope.login || get_in(scope.user || %{}, [:name]) || "system"
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      product_attrs = %{
        name: attrs.name,
        code: attrs.code,
        cost: attrs.cost,
        user_modified: username
      }

      product_attrs =
        if is_binary(attrs.image_raw) and attrs.image_raw != product.image_raw do
          product_attrs
          |> Map.put(:image_raw, attrs.image_raw)
          |> Map.put(:image_updated_at, image_timestamp(attrs.image_raw, now))
        else
          product_attrs
        end

      product_attrs =
        attrs
        |> Map.take([:active, :archived])
        |> Enum.reduce(product_attrs, fn
          {:active, value}, acc -> Map.put(acc, :active, status_flag(value))
          {:archived, value}, acc -> Map.put(acc, :archived, archived_flag(value))
        end)

      result =
        Repo.transaction(fn ->
          with {:ok, updated} <-
                 product |> Product.changeset(product_attrs) |> Repo.update(prefix: tenant),
               :ok <- save_prices(attrs.prices, updated.id, username, now, tenant) do
            updated
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      case result do
        {:ok, updated} ->
          InventoryEvents.broadcast(tenant, attrs.store_id, [updated.id])
          {:ok, updated}

        error ->
          error
      end
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def update_status(%Scope{tenant: tenant} = scope, product_id, attrs) do
    with true <- Scope.allowed?(scope, "product.edit"),
         store_id when is_integer(store_id) and store_id > 0 <- attrs.store_id,
         {:ok, _tenant} <- TigooServer.Retaily.InventoryContext.authorize_store(scope, store_id),
         %Product{} = product <- Repo.get(Product, product_id, prefix: tenant) do
      username = scope.login || get_in(scope.user || %{}, [:name]) || "system"

      product_attrs =
        attrs
        |> Map.take([:active, :archived])
        |> Enum.reduce(%{user_modified: username}, fn
          {:active, value}, acc -> Map.put(acc, :active, status_flag(value))
          {:archived, value}, acc -> Map.put(acc, :archived, archived_flag(value))
        end)

      case product |> Product.changeset(product_attrs) |> Repo.update(prefix: tenant) do
        {:ok, updated} ->
          InventoryEvents.broadcast_many(tenant, store_ids(tenant), [updated.id])
          {:ok, updated}

        error ->
          error
      end
    else
      false -> {:error, :forbidden}
      nil -> {:error, :not_found}
      _ -> {:error, :invalid_product}
    end
  end

  defp default_price?(prices) do
    if Enum.any?(prices, &(&1.pricing_id == 1 and is_number(&1.price) and &1.price >= 0)),
      do: :ok,
      else: {:error, :default_price_required}
  end

  defp status_flag(value) when value in [1, "1", true, "true", "on"], do: 1
  defp status_flag(_), do: 0

  defp archived_flag(value) when value in [1, "1", true, "true", "on"], do: "1"
  defp archived_flag(_), do: "0"

  defp image_timestamp(image_raw, now) when is_binary(image_raw) and image_raw != "", do: now
  defp image_timestamp(_image_raw, _now), do: nil

  defp new_image_timestamp(image_raw, now) when is_binary(image_raw) and image_raw != "",
    do: NaiveDateTime.add(now, 1, :second)

  defp new_image_timestamp(_image_raw, _now), do: nil

  defp store_ids(tenant), do: Repo.all(from(store in Store, select: store.id), prefix: tenant)

  defp permitted_cost(scope, cost),
    do: if(Scope.allowed?(scope, "product.view.cost"), do: cost, else: nil)

  defp can_open_product?(scope),
    do: Scope.allowed?(scope, "product.view") or Scope.allowed?(scope, "product.edit")

  defp initialize_inventory(product_id, username, now, tenant, store_ids) do
    rows =
      Enum.map(store_ids, fn store_id ->
        %{
          product_id: product_id,
          store_id: store_id,
          quantity: 0,
          prev_quantity: 0,
          last_update: now,
          user_updated: username
        }
      end)

    if rows == [],
      do: {0, nil},
      else:
        Repo.insert_all(Inventory, rows,
          prefix: tenant,
          on_conflict: :nothing,
          conflict_target: [:product_id, :store_id]
        )
  end

  defp save_prices(prices, product_id, username, now, tenant) do
    Enum.reduce_while(prices, :ok, fn price, :ok ->
      attrs = %{
        product_id: product_id,
        pricing_id: price.pricing_id,
        price: price.price,
        user_modified: username,
        date_create: now
      }

      entry =
        Repo.one(
          from(entry in PricingList,
            where: entry.product_id == ^product_id and entry.pricing_id == ^price.pricing_id,
            limit: 1
          ),
          prefix: tenant
        )

      changeset =
        if entry,
          do: PricingList.changeset(entry, attrs),
          else: PricingList.changeset(%PricingList{}, attrs)

      case Repo.insert_or_update(changeset, prefix: tenant) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
