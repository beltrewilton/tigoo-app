defmodule TigooServerWeb.ProductCreateController do
  use TigooServerWeb, :controller

  import Ecto.Query
  alias Ecto.Changeset
  alias TigooServer.{InventoryEvents, Repo, TenantContext}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.{BusinessTime, Inventory, InventoryContext, PricingList, Product, Sql, Store}

  def create(conn, attrs) do
    with {:ok, store_id} <- positive_integer(attrs["store_id"]),
         {:ok, tenant} <- InventoryContext.authorize_store(conn.assigns.current_scope, store_id) do
      username = conn.assigns.current_scope.user.name
      now = BusinessTime.local_now(tenant)
      store_ids = store_ids(tenant)

      product_attrs =
        Map.take(attrs, ["name", "cost", "margin", "code", "img_path", "image_raw", "active", "archived"])
        |> Map.merge(%{
          "active" => status_flag(Map.get(attrs, "active", true)),
          "user_modified" => username,
          "date_create" => now,
          "image_updated_at" => new_image_timestamp(attrs["image_raw"], now),
          "archived" => archived_flag(attrs["archived"])
        })

      Repo.transaction(fn ->
        with :ok <- require_default_price(attrs["prices"]),
             {:ok, product} <-
               %Product{} |> Product.changeset(product_attrs) |> Repo.insert(prefix: tenant),
             {_, _} <- initialize_inventory(product.id, username, BusinessTime.local_now(tenant), tenant, store_ids),
             :ok <- save_prices(attrs["prices"], product.id, username, now, tenant) do
          product
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, product} ->
          InventoryEvents.broadcast_many(tenant, store_ids, [product.id])

          case Sql.active_product(product.id, store_id) do
            {:ok, product} when is_map(product) ->
              conn |> put_status(:created) |> json(mask_cost(conn.assigns.current_scope, product))

            _ ->
              conn |> put_status(:created) |> json(mask_cost(conn.assigns.current_scope, product_response(product)))
          end

        {:error, %Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: Changeset.traverse_errors(changeset, fn {message, _} -> message end)})

        {:error, :default_price_required} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "a default selling price is required"})

        {:error, _reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "prices are invalid"})
      end
    else
      {:error, :invalid_params} ->
        conn |> put_status(:bad_request) |> json(%{error: "store_id is required"})

      :error ->
        conn |> put_status(:forbidden) |> json(%{error: "store is not assigned to cashier"})
    end
  end

  def show(conn, %{"id" => id}) do
    tenant = TenantContext.tenant!()

    with {:ok, product_id} <- positive_integer(id),
         %Product{} = product <- Repo.get(Product, product_id, prefix: tenant) do
      prices =
        Repo.all(
          from(entry in PricingList,
            where: entry.product_id == ^product.id,
            select: %{pricing_id: entry.pricing_id, price: entry.price}
          ),
          prefix: tenant
        )

      product =
        product
        |> product_response()
        |> Map.put(:prices, prices)

      json(conn, mask_cost(conn.assigns.current_scope, product))
    else
      {:error, :invalid_params} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid product id"})

      nil ->
        conn |> put_status(:not_found) |> json(%{error: "product not found"})
    end
  end

  def update(conn, %{"id" => id} = attrs) do
    tenant = TenantContext.tenant!()

    with {:ok, product_id} <- positive_integer(id),
         %Product{} = product <- Repo.get(Product, product_id, prefix: tenant) do
      product_attrs =
        Map.take(attrs, ["name", "cost", "margin", "code", "img_path", "image_raw", "active", "archived"])
        |> Map.put("user_modified", conn.assigns.current_scope.user.name)

      product_attrs =
        if Map.has_key?(product_attrs, "image_raw") and product_attrs["image_raw"] != product.image_raw do
          Map.put(
            product_attrs,
            "image_updated_at",
            image_timestamp(product_attrs["image_raw"], NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second))
          )
        else
          product_attrs
        end

      product_attrs =
        product_attrs
        |> maybe_put_flag("active", attrs, &status_flag/1)
        |> maybe_put_flag("archived", attrs, &archived_flag/1)

      case product |> Product.changeset(product_attrs) |> Repo.update(prefix: tenant) do
        {:ok, updated} ->
          json(conn, mask_cost(conn.assigns.current_scope, product_response(updated)))

        {:error, %Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: Changeset.traverse_errors(changeset, fn {message, _} -> message end)})
      end
    else
      {:error, :invalid_params} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid product id"})

      nil ->
        conn |> put_status(:not_found) |> json(%{error: "product not found"})
    end
  end

  def set_prices(conn, %{"prices" => prices}) when is_list(prices) do
    with {:ok, product_id} <- positive_integer(conn.params["id"]),
         %Product{} <- Repo.get(Product, product_id, prefix: TenantContext.tenant!()) do
      tenant = TenantContext.tenant!()
      username = conn.assigns.current_scope.user.name
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      result =
        Repo.transaction(fn ->
          Enum.map(prices, &upsert_price(&1, product_id, username, now, tenant))
        end)

      case result do
        {:ok, entries} ->
          json(conn, %{entries: Enum.map(entries, &price_response/1)})

        {:error, %Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: Changeset.traverse_errors(changeset, fn {message, _} -> message end)})

        {:error, _reason} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "prices are invalid"})
      end
    else
      {:error, :invalid_params} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid product id"})

      nil ->
        conn |> put_status(:not_found) |> json(%{error: "product not found"})
    end
  end

  def set_prices(conn, _),
    do: conn |> put_status(:bad_request) |> json(%{error: "prices must be a list"})

  defp upsert_price(
         %{"pricing_id" => pricing_id, "price" => price},
         product_id,
         username,
         now,
         tenant
       ) do
    with {:ok, pricing_id} <- positive_integer(pricing_id),
         {price, ""} <- Float.parse(to_string(price)) do
      attrs = %{
        product_id: product_id,
        pricing_id: pricing_id,
        price: price,
        user_modified: username,
        date_create: now
      }

      entry =
        Repo.one(
          from(entry in PricingList,
            where: entry.product_id == ^product_id and entry.pricing_id == ^pricing_id,
            order_by: [desc: entry.id],
            limit: 1
          ),
          prefix: tenant
        )

      changeset =
        if entry,
          do: PricingList.changeset(entry, attrs),
          else: PricingList.changeset(%PricingList{}, attrs)

      case Repo.insert_or_update(changeset, prefix: tenant) do
        {:ok, value} -> value
        {:error, changeset} -> Repo.rollback(changeset)
      end
    else
      _ ->
        Repo.rollback(
          Changeset.add_error(
            %PricingList{} |> PricingList.changeset(%{}),
            :price,
            "must be a non-negative number"
          )
        )
    end
  end

  defp upsert_price(_, _product_id, _username, _now, _tenant), do: Repo.rollback(:invalid_prices)

  defp require_default_price(prices) when is_list(prices) do
    if Enum.any?(
         prices,
         &(Map.get(&1, "pricing_id") in [1, "1"] and Map.get(&1, "price") not in [nil, ""])
       ),
       do: :ok,
       else: {:error, :default_price_required}
  end

  defp require_default_price(_), do: {:error, :default_price_required}

  defp save_prices(prices, product_id, username, now, tenant) when is_list(prices) do
    Enum.each(prices, &upsert_price(&1, product_id, username, now, tenant))
    :ok
  end

  defp save_prices(_, _product_id, _username, _now, _tenant), do: {:error, :invalid_prices}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :invalid_params}
    end
  end

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_), do: {:error, :invalid_params}
  defp store_ids(tenant), do: Repo.all(from(store in Store, select: store.id), prefix: tenant)

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

  defp product_response(product),
    do: %{
      id: product.id,
      name: product.name,
      cost: product.cost,
      margin: product.margin,
      code: product.code,
      img_path: product.img_path,
      image_raw: product.image_raw,
      image_updated_at: product.image_updated_at,
      active: product.active,
      archived: product.archived
    }

  defp mask_cost(scope, product) when is_map(product) do
    if Scope.allowed?(scope, "product.view.cost"),
      do: product,
      else: Map.put(product, :cost, nil)
  end

  defp archived_flag(value) when value in [1, "1", true, "true", "on"], do: "1"
  defp archived_flag(_), do: "0"

  defp status_flag(value) when value in [1, "1", true, "true", "on"], do: 1
  defp status_flag(_), do: 0

  defp image_timestamp(image_raw, now) when is_binary(image_raw) and image_raw != "", do: now
  defp image_timestamp(_image_raw, _now), do: nil

  defp new_image_timestamp(image_raw, now) when is_binary(image_raw) and image_raw != "",
    do: NaiveDateTime.add(now, 1, :second)

  defp new_image_timestamp(_image_raw, _now), do: nil

  defp maybe_put_flag(product_attrs, key, attrs, formatter) do
    if Map.has_key?(attrs, key),
      do: Map.put(product_attrs, key, formatter.(Map.get(attrs, key))),
      else: product_attrs
  end

  defp price_response(entry),
    do: %{
      id: entry.id,
      product_id: entry.product_id,
      pricing_id: entry.pricing_id,
      price: entry.price,
      date_create: entry.date_create
    }
end
