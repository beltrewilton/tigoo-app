defmodule TigooServer.Retaily.BusinessTime do
  @moduledoc false

  import Ecto.Query

  alias TigooServer.{Repo, TenantContext}
  alias TigooServer.Accounts.Company

  @default_timezone_offset -4

  def local_now(tenant \\ nil) do
    DateTime.utc_now()
    |> DateTime.add(timezone_offset(tenant), :hour)
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:second)
  end

  def timezone_offset(tenant \\ nil) do
    tenant = tenant || TenantContext.get_tenant()

    if is_binary(tenant) and timezone_offset_column?(tenant) do
      Repo.one(from(company in Company, select: company.timezone_offset, limit: 1), prefix: tenant) ||
        @default_timezone_offset
    else
      @default_timezone_offset
    end
  rescue
    _ -> @default_timezone_offset
  end

  defp timezone_offset_column?(tenant) do
    schema = Triplex.to_prefix(tenant)

    case Repo.query(
           """
           SELECT 1
           FROM information_schema.columns
           WHERE table_schema = $1
             AND table_name = 'company'
             AND column_name = 'timezone_offset'
           LIMIT 1
           """,
           [schema]
         ) do
      {:ok, %{num_rows: 1}} -> true
      _ -> false
    end
  end
end
