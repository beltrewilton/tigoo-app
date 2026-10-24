defmodule TigooServerWeb.UserController do
  use TigooServerWeb, :controller
  alias TigooServer.Retaily.Users

  def index(conn, _), do: respond(conn, Users.list(conn.assigns.current_scope))
  def options(conn, _), do: respond(conn, Users.options(conn.assigns.current_scope))
  def show(conn, %{"id" => id}), do: with_id(conn, id, &Users.get(conn.assigns.current_scope, &1))

  def create(conn, params),
    do: respond(conn |> put_status(:created), Users.create(conn.assigns.current_scope, params))

  def update(conn, %{"id" => id} = params),
    do: with_id(conn, id, &Users.update(conn.assigns.current_scope, &1, Map.drop(params, ["id"])))

  def delete(conn, %{"id" => id}),
    do: with_id(conn, id, &Users.deactivate(conn.assigns.current_scope, &1))

  defp respond(conn, {:ok, value}), do: json(conn, value)

  defp respond(conn, {:error, :not_found}),
    do: conn |> put_status(:not_found) |> json(%{error: "not found"})

  defp respond(conn, {:error, :forbidden}),
    do: conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

  defp respond(conn, {:error, %Ecto.Changeset{} = changeset}),
    do:
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{
        errors: Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)
      })

  defp respond(conn, {:error, reason}),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})

  defp with_id(conn, id, fun) do
    case Integer.parse(id) do
      {id, ""} when id > 0 -> respond(conn, fun.(id))
      _ -> conn |> put_status(:bad_request) |> json(%{error: "invalid id"})
    end
  end
end
