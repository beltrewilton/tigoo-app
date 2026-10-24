defmodule TigooServer.InventoryEvents do
  @moduledoc false

  @pubsub TigooServer.PubSub

  def topic(tenant, store_id), do: "inventory:#{tenant}:#{store_id}"

  # All inventory consumers subscribe through the same tenant-and-store-scoped
  # topic.  Never use a global inventory topic: terminals must not receive
  # inventory activity from another tenant (or another store).
  def subscribe(tenant, store_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(tenant, store_id))

  def unsubscribe(tenant, store_id),
    do: Phoenix.PubSub.unsubscribe(@pubsub, topic(tenant, store_id))

  def broadcast(tenant, store_id, product_ids) do
    Phoenix.PubSub.broadcast(@pubsub, topic(tenant, store_id), {
      :inventory_changed,
      %{type: "inventory_changed", product_ids: Enum.uniq(product_ids)}
    })
  end

  def broadcast_many(tenant, store_ids, product_ids) do
    store_ids
    |> Enum.uniq()
    |> Enum.each(&broadcast(tenant, &1, product_ids))
  end
end
