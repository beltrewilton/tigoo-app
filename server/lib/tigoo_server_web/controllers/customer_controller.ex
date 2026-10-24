defmodule TigooServerWeb.CustomerController do
  use TigooServerWeb, :controller

  alias Ecto.Changeset
  alias TigooServer.{Repo, TenantContext}
  alias TigooServer.Retaily.{Client, Sales, Sql}

  @page_size 100

  def index(conn, params) do
    with {:ok, cursor} <- parse_cursor(params["cursor"]),
         {:ok, page} <- Sql.recent_clients_page(cursor, params["search"], limit: @page_size) do
      json(conn, %{
        entries: page.entries,
        has_more: page.has_more?,
        next_cursor: page.next_cursor
      })
    else
      {:error, :invalid_cursor} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "cursor must be a non-negative integer"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "could not load customers", details: inspect(reason)})
    end
  end

  def create(conn, params) do
    tenant = TenantContext.tenant!()

    attrs =
      customer_attrs(params, default_wholesaler?: true)

    case %Client{} |> Client.changeset(attrs) |> Repo.insert(prefix: tenant) do
      {:ok, client} ->
        conn |> put_status(:created) |> json(customer_response(client))

      {:error, %Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: Changeset.traverse_errors(changeset, fn {message, _} -> message end)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    tenant = TenantContext.tenant!()

    with {:ok, customer_id} <- parse_id(id),
         %Client{} = client <- Repo.get(Client, customer_id, prefix: tenant) do
      case client |> Client.changeset(customer_attrs(params)) |> Repo.update(prefix: tenant) do
        {:ok, client} ->
          json(conn, customer_response(client))

        {:error, %Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: Changeset.traverse_errors(changeset, fn {message, _} -> message end)})
      end
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "customer id must be a positive integer"})

      nil ->
        conn |> put_status(:not_found) |> json(%{error: "customer not found"})
    end
  end

  def purchases(conn, %{"id" => id}) do
    with {:ok, customer_id} <- parse_id(id),
         {:ok, entries} <-
           Sales.recent_customer_purchases(conn.assigns.current_scope, customer_id) do
      json(conn, %{entries: entries})
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "customer id must be a positive integer"})

      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "could not load customer purchases", details: inspect(reason)})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, customer_id} <- parse_id(id),
         {:ok, detail} <- Sales.customer_detail(conn.assigns.current_scope, customer_id) do
      json(conn, detail)
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "customer id must be a positive integer"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "customer not found"})

      {:error, :unauthorized} ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthorized"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "could not load customer", details: inspect(reason)})
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> :error
    end
  end

  defp parse_id(_), do: :error

  defp parse_cursor(nil), do: {:ok, nil}

  defp parse_cursor(cursor) when is_binary(cursor) do
    case Integer.parse(cursor) do
      {value, ""} when value >= 0 -> {:ok, value}
      _ -> {:error, :invalid_cursor}
    end
  end

  defp customer_response(client) do
    %{
      id: client.id,
      name: client.name,
      document_id: client.document_id,
      address: client.address,
      celphone: client.celphone,
      email: client.email,
      date_create: client.date_create,
      wholesaler: client.wholesaler,
      is_wholesaler: client.wholesaler == 1
    }
  end

  defp customer_attrs(params, opts \\ []) do
    params
    |> put_wholesaler_attr(Keyword.get(opts, :default_wholesaler?, false))
    |> Map.take(["name", "document_id", "address", "celphone", "email", "wholesaler"])
  end

  defp put_wholesaler_attr(params, _default?) when is_map_key(params, "is_wholesaler") do
    Map.put(params, "wholesaler", wholesaler_value(params["is_wholesaler"]))
  end

  defp put_wholesaler_attr(params, true) when not is_map_key(params, "wholesaler") do
    Map.put(params, "wholesaler", 0)
  end

  defp put_wholesaler_attr(params, _default?), do: params

  defp wholesaler_value(value) when value in [true, 1, "1", "true", "on"], do: 1
  defp wholesaler_value(_value), do: 0
end
