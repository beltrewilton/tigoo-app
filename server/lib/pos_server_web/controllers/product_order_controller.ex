defmodule TigooServerWeb.ProductOrderController do
  use TigooServerWeb, :controller

  alias Ecto.Changeset
  alias TigooServer.Retaily.Orders

  def index(conn, %{"store_id" => store_id} = params) do
    case Integer.parse(store_id) do
      {id, ""} when id > 0 ->
        case Orders.list_orders(conn.assigns.current_scope, id, params["status"]) do
          {:ok, orders} -> json(conn, orders)
          {:error, reason} -> error(conn, reason)
        end

      _ ->
        error(conn, :invalid_params)
    end
  end

  def index(conn, _), do: error(conn, :invalid_params)

  def create(conn, params) do
    case Orders.create_order(conn.assigns.current_scope, params) do
      {:ok, order} -> conn |> put_status(:created) |> json(order)
      {:error, reason} -> error(conn, reason)
    end
  end

  def receive(conn, %{"id" => id} = params) do
    with {:ok, order_id} <- parse_id(id) do
      case Orders.receive_order(conn.assigns.current_scope, order_id, Map.drop(params, ["id"])) do
        {:ok, order} -> json(conn, order)
        {:error, reason} -> error(conn, reason)
      end
    else
      :error -> error(conn, :invalid_params)
    end
  end

  defp parse_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error

  defp error(conn, %Changeset{} = changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: Changeset.traverse_errors(changeset, fn {message, _} -> message end)})
  end

  defp error(conn, :unauthorized),
    do: conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})

  defp error(conn, :not_found), do: conn |> put_status(:not_found) |> json(%{error: "not found"})

  defp error(conn, :forbidden_store),
    do: conn |> put_status(:forbidden) |> json(%{error: "store is not assigned to cashier"})

  defp error(conn, reason),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
end
