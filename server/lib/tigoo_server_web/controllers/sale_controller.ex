defmodule TigooServerWeb.SaleController do
  use TigooServerWeb, :controller

  alias Ecto.Changeset
  alias TigooServer.Retaily.{InventoryContext, Sales, Sql}

  @page_size 100

  def index(conn, params) do
    case Sales.list_sales(conn.assigns.current_scope, normalize_filters(params)) do
      {:ok, sales} -> json(conn, %{entries: sales})
      {:error, reason} -> error(conn, reason)
    end
  end

  def report(conn, params) do
    with {:ok, cursor} <- parse_cursor(params["cursor"]),
         {:ok, store_id} <- parse_store_id(params["store_id"]),
         {:ok, date_from} <- parse_date(params["date_from"]),
         {:ok, date_to} <- parse_date(params["date_to"]),
         {:ok, invoice_status} <- parse_invoice_status(params["invoice_status"]),
         :ok <- valid_date_range(date_from, date_to),
         {:ok, _tenant} <- InventoryContext.authorize_store(conn.assigns.current_scope, store_id),
         {:ok, page} <-
           Sql.sales_report_page(store_id, cursor,
             limit: @page_size,
             search: params["search"],
             date_from: date_from,
             date_to: date_to,
             invoice_status: invoice_status
           ),
         {:ok, summary} <-
           Sql.sales_report_summary(store_id,
             search: params["search"],
             date_from: date_from,
             date_to: date_to
           ) do
      json(conn, %{
        entries: page.entries,
        has_more: page.has_more?,
        next_cursor: page.next_cursor,
        summary: summary
      })
    else
      {:error, :invalid_cursor} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "cursor is invalid"})

      :error ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "store is not assigned to cashier"})

      {:error, :invalid_store_id} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "store_id must be a positive integer"})

      {:error, :invalid_date} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "date filters must use YYYY-MM-DD and date_from cannot be after date_to"
        })

      {:error, :invalid_invoice_status} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invoice_status must be open, close, or cancelled"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "could not load sales report", details: inspect(reason)})
    end
  end

  def show(conn, %{"id" => id}) do
    case parse_id(id) do
      {:ok, sale_id} ->
        case Sales.get_sale(conn.assigns.current_scope, sale_id) do
          {:ok, sale} -> json(conn, sale)
          {:error, reason} -> error(conn, reason)
        end

      :error ->
        error(conn, :invalid_id)
    end
  end

  def create(conn, params) do
    case Sales.create_sale(conn.assigns.current_scope, params) do
      {:ok, sale} -> conn |> put_status(:created) |> json(sale)
      {:error, reason} -> error(conn, reason)
    end
  end

  def add_payment(conn, %{"id" => id} = params) do
    with {:ok, sale_id} <- parse_id(id) do
      case Sales.add_payment(conn.assigns.current_scope, sale_id, Map.drop(params, ["id"])) do
        {:ok, sale} -> json(conn, sale)
        {:error, reason} -> error(conn, reason)
      end
    else
      :error -> error(conn, :invalid_id)
    end
  end

  def cancel(conn, %{"id" => id}) do
    with {:ok, sale_id} <- parse_id(id) do
      case Sales.cancel_sale(conn.assigns.current_scope, sale_id) do
        {:ok, sale} -> json(conn, sale)
        {:error, reason} -> error(conn, reason)
      end
    else
      :error -> error(conn, :invalid_id)
    end
  end

  defp normalize_filters(params) do
    Enum.reduce(params, %{}, fn
      {key, value}, acc when key in ["store_id", "client_id"] ->
        case parse_id(value) do
          {:ok, id} -> Map.put(acc, key, id)
          :error -> acc
        end

      {key, value}, acc when key in ["cashier", "invoice_status"] ->
        Map.put(acc, key, value)

      {key, value}, acc when key in ["date_from", "date_to"] ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, date} -> Map.put(acc, key, date)
          _ -> acc
        end

      _, acc ->
        acc
    end)
  end

  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error

  defp parse_store_id(value) do
    case parse_id(value) do
      {:ok, store_id} -> {:ok, store_id}
      :error -> {:error, :invalid_store_id}
    end
  end

  defp parse_cursor(nil), do: {:ok, nil}

  defp parse_cursor(cursor) when is_binary(cursor) do
    with [date_create, id] <- String.split(cursor, ",", parts: 2),
         {:ok, date_create} <- NaiveDateTime.from_iso8601(date_create),
         {id, ""} <- Integer.parse(id),
         true <- id >= 0 do
      {:ok, %{date_create: date_create, id: id}}
    else
      _ -> {:error, :invalid_cursor}
    end
  end

  defp parse_cursor(_cursor), do: {:error, :invalid_cursor}

  defp parse_date(nil), do: {:ok, nil}

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_date}
    end
  end

  defp parse_date(_), do: {:error, :invalid_date}

  defp valid_date_range(%Date{} = date_from, %Date{} = date_to) do
    if Date.compare(date_from, date_to) == :gt, do: {:error, :invalid_date}, else: :ok
  end

  defp valid_date_range(_, _), do: :ok

  defp parse_invoice_status(nil), do: {:ok, nil}

  defp parse_invoice_status(status) when status in ["open", "close", "cancelled"],
    do: {:ok, status}

  defp parse_invoice_status(_), do: {:error, :invalid_invoice_status}

  def ecf_test_status(conn, %{"id" => "ecf-test-" <> id}), do: ecf_test_status(conn, %{"id" => id})
  def ecf_test_status(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, invoice} <- TigooServer.Fe.TestInvoices.get(conn.assigns.current_scope, id) do
      json(conn, invoice)
    else
      :error -> error(conn, :invalid_id)
      {:error, reason} -> error(conn, reason)
    end
  end

  defp error(conn, {:ecf_test_not_configured, message}),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: message})

  defp error(conn, {:ecf_document, message}),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: message})

  defp error(conn, %Changeset{} = changeset),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{errors: Changeset.traverse_errors(changeset, fn {message, _} -> message end)})

  defp error(conn, :unauthorized),
    do: conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})

  defp error(conn, :not_found), do: conn |> put_status(:not_found) |> json(%{error: "not found"})

  defp error(conn, :forbidden_store),
    do: conn |> put_status(:forbidden) |> json(%{error: "store is not assigned to cashier"})

  defp error(conn, :forbidden), do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

  defp error(conn, reason),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
end
