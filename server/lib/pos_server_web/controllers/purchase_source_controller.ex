defmodule TigooServerWeb.PurchaseSourceController do
  use TigooServerWeb, :controller

  alias TigooServer.Retaily.Orders

  def index(conn, %{"store_id" => store_id}) do
    case positive_integer(store_id) do
      {:ok, id} ->
        case Orders.list_purchase_sources(conn.assigns.current_scope, id) do
          {:ok, entries} ->
            json(conn, %{entries: entries})

          :error ->
            conn |> put_status(:forbidden) |> json(%{error: "store is not assigned to cashier"})

          {:error, reason} ->
            conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
        end

      :error ->
        conn |> put_status(:bad_request) |> json(%{error: "store_id is required"})
    end
  end

  def index(conn, _params),
    do: conn |> put_status(:bad_request) |> json(%{error: "store_id is required"})

  defp positive_integer(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> :error
    end
  end
end
