defmodule TigooServerWeb.ProductController do
  use TigooServerWeb, :controller

  alias TigooServer.Retaily.{InventoryContext, Sql}
  alias TigooServer.Accounts.Scope

  @page_size 100

  def index(conn, params) do
    with {:ok, cursor} <- parse_cursor(params["cursor"]),
         {:ok, store_id} <- parse_store_id(params["store_id"]),
         {:ok, _tenant} <- InventoryContext.authorize_store(conn.assigns.current_scope, store_id),
         {:ok, page} <-
           Sql.active_products_page(cursor,
             limit: @page_size,
             store_id: store_id,
             search: params["search"]
           ) do
      json(conn, %{
        entries: Enum.map(page.entries, &mask_cost(conn.assigns.current_scope, &1)),
        has_more: page.has_more?,
        next_cursor: page.next_cursor
      })
    else
      {:error, :invalid_cursor} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "cursor must be a non-negative integer"})

      {:error, :invalid_store_id} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "store_id must be a positive integer"})

      :error ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "store is not assigned to cashier"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "could not load products", details: inspect(reason)})
    end
  end

  defp parse_store_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {store_id, ""} when store_id > 0 -> {:ok, store_id}
      _ -> {:error, :invalid_store_id}
    end
  end

  defp parse_store_id(_), do: {:error, :invalid_store_id}

  defp parse_cursor(nil), do: {:ok, nil}

  defp parse_cursor(cursor) when is_binary(cursor) do
    case Integer.parse(cursor) do
      {value, ""} when value >= 0 -> {:ok, value}
      _ -> {:error, :invalid_cursor}
    end
  end

  defp mask_cost(scope, product) when is_map(product) do
    if Scope.allowed?(scope, "product.view.cost") do
      product
    else
      product
      |> Map.put(:cost, nil)
      |> Map.put(:product_cost, nil)
      |> Map.put("cost", nil)
      |> Map.put("product_cost", nil)
    end
  end
end
