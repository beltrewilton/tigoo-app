defmodule TigooServer.FeSeedStore do
  @moduledoc false
  use GenServer

  @ttl 300
  @capacity 10_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def put(seed), do: GenServer.call(__MODULE__, {:put, seed})
  def consume(seed), do: GenServer.call(__MODULE__, {:consume, seed})

  @impl true
  def init(_opts) do
    Process.send_after(self(), :cleanup, 60_000)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:put, seed}, _from, state) do
    state = prune(state)

    if map_size(state) < @capacity do
      {:reply, :ok, Map.put(state, seed.valor, {seed.fecha, now() + @ttl})}
    else
      {:reply, {:error, :seed_capacity}, state}
    end
  end

  def handle_call({:consume, seed}, _from, state) do
    case Map.get(state, seed.valor) do
      {fecha, expires} when fecha == seed.fecha ->
        result = if expires > now(), do: :ok, else: {:error, :invalid_seed}
        {:reply, result, Map.delete(state, seed.valor)}

      _ ->
        {:reply, {:error, :invalid_seed}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    Process.send_after(self(), :cleanup, 60_000)
    {:noreply, prune(state)}
  end

  defp prune(state) do
    time = now()
    Map.reject(state, fn {_key, {_fecha, expires}} -> expires <= time end)
  end

  defp now, do: System.monotonic_time(:second)
end
