defmodule TigooServer.Repo.Migrations.CreateProductTraces do
  use Ecto.Migration

  def change do
    create table(:product_traces) do
      add :product_id, references(:product, type: :bigint), null: false
      add :store_id, references(:app_store), null: false
      add :event_type, :string, size: 30, null: false
      add :quantity_before, :integer, null: false
      add :quantity_change, :integer, null: false
      add :quantity_after, :integer, null: false
      add :unit_cost, :float
      add :unit_price, :float
      add :reference_type, :string, size: 30
      add :reference_id, :bigint
      add :operator_username, :string, size: 90
      add :customer_id, :bigint
      add :customer_name, :string, size: 200
      add :source_store_id, references(:app_store)
      add :destination_store_id, references(:app_store)
      add :metadata, :map, default: %{}, null: false
      timestamps(updated_at: false, type: :naive_datetime)
    end

    create constraint(:product_traces, :product_traces_event_type_valid,
             check: "event_type IN ('sale', 'inventory_adjustment', 'purchase', 'store_transfer_out', 'store_transfer_in')"
           )

    create index(:product_traces, [:product_id, :inserted_at])
    create index(:product_traces, [:store_id, :inserted_at])
    create index(:product_traces, [:event_type])
    create index(:product_traces, [:reference_type, :reference_id])
  end
end
