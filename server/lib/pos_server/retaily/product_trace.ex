defmodule TigooServer.Retaily.ProductTrace do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset
  alias TigooServer.Retaily.BusinessTime

  @event_types ~w(sale inventory_adjustment purchase store_transfer_out store_transfer_in)
  @timestamps_opts [type: :naive_datetime, autogenerate: {BusinessTime, :local_now, []}]

  schema "product_traces" do
    field :event_type, :string
    field :quantity_before, :integer
    field :quantity_change, :integer
    field :quantity_after, :integer
    field :unit_cost, :float
    field :unit_price, :float
    field :reference_type, :string
    field :reference_id, :integer
    field :operator_username, :string
    field :customer_id, :integer
    field :customer_name, :string
    field :metadata, :map, default: %{}
    belongs_to :product, TigooServer.Retaily.Product, type: :integer
    belongs_to :store, TigooServer.Retaily.Store, type: :integer
    belongs_to :source_store, TigooServer.Retaily.Store, type: :integer
    belongs_to :destination_store, TigooServer.Retaily.Store, type: :integer
    timestamps(updated_at: false, type: :naive_datetime)
  end

  def changeset(trace, attrs) do
    trace
    |> cast(attrs, [
      :product_id,
      :store_id,
      :event_type,
      :quantity_before,
      :quantity_change,
      :quantity_after,
      :unit_cost,
      :unit_price,
      :reference_type,
      :reference_id,
      :operator_username,
      :customer_id,
      :customer_name,
      :source_store_id,
      :destination_store_id,
      :metadata
    ])
    |> validate_required([
      :product_id,
      :store_id,
      :event_type,
      :quantity_before,
      :quantity_change,
      :quantity_after
    ])
    |> validate_inclusion(:event_type, @event_types)
    |> check_constraint(:event_type, name: :product_traces_event_type_valid)
  end
end
