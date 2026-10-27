defmodule TigooServer.Tenants do
  @moduledoc """
  Central tenant validation and registry access.

  Tenant identifiers are public subdomain slugs. The ETS registry stores only
  validated tenants so request-time checks avoid database queries.
  """

  use GenServer

  alias TigooServer.Repo

  @table __MODULE__
  @reserved ~w(www api admin app mail support status assets static docs auth login signup billing)
  @format ~r/^[a-z][a-z0-9_-]{2,62}$/

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :protected, read_concurrency: true])
    load_registry()
    {:ok, %{}}
  end

  def list, do: :ets.tab2list(@table) |> Enum.map(&elem(&1, 0)) |> Enum.sort()

  def refresh, do: GenServer.call(__MODULE__, :refresh)

  def put(tenant) when is_binary(tenant), do: GenServer.call(__MODULE__, {:put, tenant})
  def put(_), do: {:error, :invalid_tenant}

  def handle_call(:refresh, _from, state) do
    :ets.delete_all_objects(@table)
    load_registry()
    {:reply, :ok, state}
  end

  def handle_call({:put, tenant}, _from, state) do
    reply =
      if valid_identifier?(tenant) do
        :ets.insert(@table, {tenant})
        :ok
      else
        {:error, :invalid_tenant}
      end

    {:reply, reply, state}
  end

  defp load_registry do
    Ecto.Adapters.SQL.query!(
      Repo,
      "SELECT schema_name FROM information_schema.schemata",
      []
    )
    |> Map.fetch!(:rows)
    |> List.flatten()
    |> Enum.reject(&Triplex.reserved_tenant?/1)
    |> Enum.filter(&valid_identifier?/1)
    |> Enum.each(fn tenant -> :ets.insert(@table, {tenant}) end)
  end

  def exists?(tenant) when is_binary(tenant) do
    valid_identifier?(tenant) and :ets.member(@table, tenant)
  rescue
    ArgumentError -> false
  end

  def exists?(_), do: false

  def valid_identifier?(tenant) when is_binary(tenant),
    do: String.match?(tenant, @format) and tenant not in @reserved

  def valid_identifier?(_), do: false

  def reserved?(tenant) when is_binary(tenant), do: tenant in @reserved
  def reserved?(_), do: false
end
