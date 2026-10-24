defmodule TigooServerWeb.InventoryController do
  use TigooServerWeb, :controller

  alias Ecto.Changeset
  alias TigooServer.Retaily.{InventoryContext, Orders, Sql}

  def summary(conn, params) do
    with {:ok, store_id} <- positive_integer(params["store_id"]),
         {:ok, _tenant} <- InventoryContext.authorize_store(conn.assigns.current_scope, store_id),
         {:ok, summary} <- Sql.inventory_summary(store_id) do
      json(conn, %{summary: summary})
    else
      {:error, :invalid_params} ->
        conn |> put_status(:bad_request) |> json(%{error: "store_id is required"})

      :error ->
        conn |> put_status(:forbidden) |> json(%{error: "store is not assigned to cashier"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def index(conn, params) do
    with {:ok, store_id} <- positive_integer(params["store_id"]),
         {:ok, inventory_filter} <- inventory_filter(params["inventory_filter"]),
         {:ok, entries} <-
           inventory_entries(
             conn.assigns.current_scope,
             store_id,
             params["product_ids"],
             params["all_stores"],
             inventory_filter
           ) do
      json(conn, %{entries: entries})
    else
      {:error, :invalid_params} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "store_id, product_ids, or inventory_filter is invalid"})

      :error ->
        conn |> put_status(:forbidden) |> json(%{error: "store is not assigned to cashier"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  defp inventory_entries(scope, store_id, nil, _all_stores, inventory_filter),
    do: InventoryContext.list(scope, store_id, inventory_filter)

  defp inventory_entries(scope, store_id, ids, "true", _inventory_filter) do
    with {:ok, [product_id]} <- product_ids(ids) do
      InventoryContext.product_store_quantities(scope, store_id, product_id)
    end
  end

  defp inventory_entries(scope, store_id, ids, _all_stores, _inventory_filter) do
    with {:ok, product_ids} <- product_ids(ids) do
      InventoryContext.quantities(scope, store_id, product_ids)
    end
  end

  def adjust(conn, params) do
    case Orders.adjust_inventory(conn.assigns.current_scope, params) do
      {:ok, inventory} ->
        json(conn, %{
          id: inventory.id,
          product_id: inventory.product_id,
          store_id: inventory.store_id,
          prev_quantity: inventory.prev_quantity,
          quantity: inventory.quantity,
          last_update: inventory.last_update,
          user_updated: inventory.user_updated
        })

      {:error, %Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: Changeset.traverse_errors(changeset, fn {message, _} -> message end)})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "inventory or product not found"})

      {:error, :forbidden_store} ->
        conn |> put_status(:forbidden) |> json(%{error: "store is not assigned to cashier"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def traces(conn, %{"product_id" => product_id, "store_id" => store_id}) do
    with {:ok, product_id} <- positive_integer(product_id),
         {:ok, store_id} <- positive_integer(store_id),
         {:ok, entries} <-
           InventoryContext.product_traces(conn.assigns.current_scope, store_id, product_id) do
      json(conn, %{entries: entries})
    else
      {:error, :invalid_params} ->
        conn |> put_status(:bad_request) |> json(%{error: "product_id and store_id are required"})

      :error ->
        conn |> put_status(:forbidden) |> json(%{error: "store is not assigned to cashier"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  def move(conn, params) do
    case Orders.move_inventory(conn.assigns.current_scope, params) do
      {:ok, result} ->
        json(conn, result)

      {:error, %Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: Changeset.traverse_errors(changeset, fn {message, _} -> message end)})

      {:error, :same_store} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "origin and destination stores must be different"})

      {:error, :insufficient_inventory} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "origin store does not have enough available inventory"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "inventory, product, or store not found"})

      {:error, :forbidden_store} ->
        conn |> put_status(:forbidden) |> json(%{error: "store is not assigned to cashier"})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  defp product_ids(value) when is_binary(value) do
    ids = value |> String.split(",", trim: true) |> Enum.map(&positive_integer/1)

    if ids != [] and Enum.all?(ids, &match?({:ok, _}, &1)),
      do: {:ok, ids |> Enum.map(fn {:ok, id} -> id end) |> Enum.uniq()},
      else: {:error, :invalid_params}
  end

  defp product_ids(_), do: {:error, :invalid_params}

  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :invalid_params}
    end
  end

  defp positive_integer(_), do: {:error, :invalid_params}

  defp inventory_filter(nil), do: {:ok, nil}
  defp inventory_filter(filter) when filter in ["negative", "uncosted"], do: {:ok, filter}
  defp inventory_filter(_), do: {:error, :invalid_params}
end
