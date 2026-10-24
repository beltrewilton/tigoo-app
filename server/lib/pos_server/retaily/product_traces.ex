defmodule TigooServer.Retaily.ProductTraces do
  @moduledoc false

  import Ecto.Query
  require Logger

  alias TigooServer.Repo
  alias TigooServer.TenantContext
  alias TigooServer.Retaily.{InventoryContext, ProductTrace, Store}

  # Audit writes deliberately run after the owning transaction. A failed trace is
  # logged but never changes the outcome of a sale or inventory operation.
  def dispatch(tenant, traces) when is_list(traces) do
    try do
      Task.Supervisor.start_child(TigooServer.TaskSupervisor, fn ->
        TenantContext.put_tenant(tenant)

        Enum.each(traces, fn attrs ->
          try do
            case %ProductTrace{}
                 |> ProductTrace.changeset(attrs)
                 |> Repo.insert(prefix: tenant) do
              {:ok, _trace} ->
                :ok

              {:error, changeset} ->
                Logger.error("product_trace_insert_failed: #{inspect(changeset.errors)}")
            end
          rescue
            error -> Logger.error("product_trace_insert_crashed: #{Exception.message(error)}")
          end
        end)
      end)
      |> case do
        {:ok, _pid} -> :ok
        {:error, reason} -> Logger.error("product_trace_dispatch_failed: #{inspect(reason)}")
      end
    rescue
      error -> Logger.error("product_trace_dispatch_crashed: #{Exception.message(error)}")
    end

    :ok
  end

  def list(scope, store_id, product_id) do
    with {:ok, tenant} <- InventoryContext.authorize_store(scope, store_id) do
      traces =
        Repo.all(
          from(trace in ProductTrace,
            join: store in Store,
            on: store.id == trace.store_id,
            left_join: source in Store,
            on: source.id == trace.source_store_id,
            left_join: destination in Store,
            on: destination.id == trace.destination_store_id,
            where: trace.product_id == ^product_id,
            order_by: [desc: trace.inserted_at, desc: trace.id],
            select: %{
              id: trace.id,
              event_type: trace.event_type,
              store_name: store.name,
              quantity_before: trace.quantity_before,
              quantity_change: trace.quantity_change,
              quantity_after: trace.quantity_after,
              operator_username: trace.operator_username,
              reference_type: trace.reference_type,
              reference_id: trace.reference_id,
              customer_name: trace.customer_name,
              source_store_name: source.name,
              destination_store_name: destination.name,
              metadata: trace.metadata,
              inserted_at: trace.inserted_at
            }
          ),
          prefix: tenant
        )

      {:ok, traces}
    end
  end
end
