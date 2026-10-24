defmodule TigooServer.Retaily.Sql do
  @moduledoc """
  Executes version-controlled SQL files against a Triplex tenant schema.

  SQL files live under `server/sql/retaily` and use `{{prefix}}` for the
  tenant schema identifier. Values always use PostgreSQL positional parameters
  (`$1`, `$2`, ...) and are passed separately to `TigooServer.Repo.query/3`.
  """

  alias TigooServer.{Repo, TenantContext}

  @sql_directory Path.expand("../../../sql/retaily", __DIR__)
  @max_page_size 100
  @tax_rate Decimal.new("0.18")

  @type page :: %{
          entries: [map()],
          has_more?: boolean(),
          next_cursor:
            non_neg_integer() | %{date_create: NaiveDateTime.t(), id: non_neg_integer()} | nil
        }

  @spec active_products_page(non_neg_integer() | nil, keyword()) ::
          {:ok, page()} | {:error, term()}
  def active_products_page(after_id \\ nil, opts \\ []) do
    tenant = TenantContext.tenant!()

    with :ok <- validate_cursor(after_id),
         {:ok, page_size} <- page_size(opts),
         {:ok, store_id} <- store_id(opts),
         {:ok, result} <-
           run(tenant, "active_products", [
             after_id,
             page_size + 1,
             @tax_rate,
             store_id,
             normalize_search(Keyword.get(opts, :search)),
             nil
           ]) do
      entries = result |> rows_as_maps() |> Enum.take(page_size)
      has_more? = result.num_rows > page_size

      {:ok,
       %{
         entries: entries,
         has_more?: has_more?,
         next_cursor: next_cursor(entries, has_more?)
       }}
    end
  end

  @spec active_product(pos_integer(), pos_integer()) :: {:ok, map() | nil} | {:error, term()}
  def active_product(product_id, store_id) do
    tenant = TenantContext.tenant!()

    with {:ok, valid_store_id} <- store_id(store_id),
         {:ok, result} <-
           run(tenant, "active_products", [nil, 1, @tax_rate, valid_store_id, nil, product_id]) do
      {:ok, result |> rows_as_maps() |> List.first()}
    end
  end

  @spec recent_clients_page(non_neg_integer() | nil, String.t() | nil, keyword()) ::
          {:ok, page()} | {:error, term()}
  def recent_clients_page(before_id \\ nil, search \\ nil, opts \\ []) do
    tenant = TenantContext.tenant!()

    with :ok <- validate_cursor(before_id),
         {:ok, page_size} <- page_size(opts),
         {:ok, result} <-
           run(tenant, "recent_clients", [before_id, normalize_search(search), page_size + 1]) do
      entries = result |> rows_as_maps() |> Enum.take(page_size)
      has_more? = result.num_rows > page_size

      {:ok,
       %{
         entries: entries,
         has_more?: has_more?,
         next_cursor: next_cursor(entries, has_more?)
       }}
    end
  end

  @spec sales_report_page(
          pos_integer(),
          %{date_create: NaiveDateTime.t(), id: non_neg_integer()} | nil,
          keyword()
        ) ::
          {:ok, page()} | {:error, term()}
  def sales_report_page(store_id, cursor \\ nil, opts \\ []) do
    tenant = TenantContext.tenant!()

    with :ok <- validate_sales_report_cursor(cursor),
         {:ok, page_size} <- page_size(opts),
         {:ok, store_id} <- store_id(store_id),
         {:ok, result} <-
           run(tenant, "sales_report", [
             cursor_date(cursor),
             cursor_id(cursor),
             page_size + 1,
             store_id,
             normalize_search(Keyword.get(opts, :search)),
             Keyword.get(opts, :date_from),
             Keyword.get(opts, :date_to),
             Keyword.get(opts, :invoice_status)
           ]) do
      entries = result |> rows_as_maps() |> Enum.take(page_size)
      has_more? = result.num_rows > page_size

      {:ok,
       %{
         entries: entries,
         has_more?: has_more?,
         next_cursor: sales_report_next_cursor(entries, has_more?)
       }}
    end
  end

  @spec sales_report_summary(pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def sales_report_summary(store_id, opts \\ []) do
    tenant = TenantContext.tenant!()

    with {:ok, store_id} <- store_id(store_id),
         {:ok, result} <-
           run(tenant, "sales_report_summary", [
             store_id,
             normalize_search(Keyword.get(opts, :search)),
             Keyword.get(opts, :date_from),
             Keyword.get(opts, :date_to)
           ]) do
      {:ok, result |> rows_as_maps() |> List.first()}
    end
  end

  @spec inventory_summary(pos_integer()) :: {:ok, map()} | {:error, term()}
  def inventory_summary(store_id) do
    tenant = TenantContext.tenant!()

    with {:ok, store_id} <- store_id(store_id),
         {:ok, result} <- run(tenant, "inventory_summary", [store_id]) do
      {:ok, result |> rows_as_maps() |> List.first()}
    end
  end

  @spec run(String.t(), String.t(), list()) :: {:ok, Postgrex.Result.t()} | {:error, term()}
  def run(tenant, statement_name, params \\ []) when is_list(params) do
    with {:ok, sql} <- read(statement_name) do
      Repo.query(render(sql, tenant), params)
    end
  end

  @spec read(String.t()) :: {:ok, String.t()} | {:error, :invalid_statement | :enoent | term()}
  def read(statement_name) do
    with :ok <- valid_statement_name(statement_name) do
      File.read(Path.join(@sql_directory, "#{statement_name}.sql"))
    end
  end

  defp rows_as_maps(%Postgrex.Result{columns: columns, rows: rows}) do
    Enum.map(rows, &Map.new(Enum.zip(columns, &1)))
  end

  defp render(sql, tenant) when is_binary(tenant) do
    String.replace(sql, "{{prefix}}", quote_identifier(Triplex.to_prefix(tenant)))
  end

  defp quote_identifier(identifier) do
    escaped = String.replace(identifier, "\"", "\"\"")
    "\"#{escaped}\""
  end

  defp next_cursor(entries, true), do: entries |> List.last() |> Map.fetch!("id")
  defp next_cursor(_entries, false), do: nil

  defp sales_report_next_cursor(entries, true) do
    entries
    |> List.last()
    |> then(fn entry ->
      %{date_create: Map.fetch!(entry, "date_create"), id: Map.fetch!(entry, "id")}
    end)
  end

  defp sales_report_next_cursor(_entries, false), do: nil

  defp cursor_date(nil), do: nil
  defp cursor_date(%{date_create: date_create}), do: date_create

  defp cursor_id(nil), do: nil
  defp cursor_id(%{id: id}), do: id

  defp page_size(opts) do
    case Keyword.get(opts, :limit, 50) do
      limit when is_integer(limit) and limit > 0 and limit <= @max_page_size -> {:ok, limit}
      _ -> {:error, {:invalid_page_size, "must be between 1 and #{@max_page_size}"}}
    end
  end

  defp store_id(opts) when is_list(opts), do: opts |> Keyword.get(:store_id) |> store_id()

  defp store_id(store_id) do
    case store_id do
      store_id when is_integer(store_id) and store_id > 0 -> {:ok, store_id}
      _ -> {:error, :invalid_store_id}
    end
  end

  defp validate_cursor(nil), do: :ok
  defp validate_cursor(cursor) when is_integer(cursor) and cursor >= 0, do: :ok
  defp validate_cursor(_cursor), do: {:error, :invalid_cursor}

  defp validate_sales_report_cursor(nil), do: :ok

  defp validate_sales_report_cursor(%{date_create: %NaiveDateTime{}, id: id})
       when is_integer(id) and id >= 0,
       do: :ok

  defp validate_sales_report_cursor(_cursor), do: {:error, :invalid_cursor}

  defp normalize_search(search) when is_binary(search), do: String.trim(search)
  defp normalize_search(_search), do: nil

  defp valid_statement_name(name) when is_binary(name) do
    if Regex.match?(~r/\A[a-z0-9_]+\z/, name), do: :ok, else: {:error, :invalid_statement}
  end

  defp valid_statement_name(_name), do: {:error, :invalid_statement}
end
