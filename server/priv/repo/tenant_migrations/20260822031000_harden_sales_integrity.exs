defmodule TigooServer.Repo.Migrations.HardenSalesIntegrity do
  use Ecto.Migration

  def up do
    # The imported Retaily schema stores money as double precision. Convert
    # existing values explicitly and round them to the scale used by Ecto's
    # :decimal fields before sales code starts writing Decimal values.
    convert_money_columns(:sale, [:amount, :sub, :discount, :tax_amount, :delivery_charge])
    convert_money_columns(:sale_line, [:amount, :tax_amount, :discount, :total_amount])
    convert_money_columns(:sale_paid, [:amount])

    alter table(:sale_line) do
      modify :sale_id, references(:sale, type: :bigint, on_delete: :restrict)
      modify :product_id, references(:product, type: :bigint, on_delete: :restrict)
    end

    alter table(:sale_paid) do
      modify :sale_id, references(:sale, type: :bigint, on_delete: :restrict)
    end

    create unique_index(:app_inventory, [:product_id, :store_id])
    create index(:sale_line, [:sale_id])
    create index(:sale_paid, [:sale_id])
    create unique_index(:sale, [:sequence_type, :sequence])
  end

  def down do
    drop unique_index(:sale, [:sequence_type, :sequence])
    drop index(:sale_paid, [:sale_id])
    drop index(:sale_line, [:sale_id])
    drop unique_index(:app_inventory, [:product_id, :store_id])

    alter table(:sale_paid) do
      modify :sale_id, :bigint
      modify :amount, :float
    end

    alter table(:sale_line) do
      modify :product_id, :bigint
      modify :sale_id, :bigint
      modify :total_amount, :float
      modify :discount, :float
      modify :tax_amount, :float
      modify :amount, :float
    end

    alter table(:sale) do
      modify :delivery_charge, :float
      modify :tax_amount, :float
      modify :discount, :float
      modify :sub, :float
      modify :amount, :float
    end
  end

  defp convert_money_columns(table, columns) do
    schema = quoted_identifier(prefix() || "public")
    table = quoted_identifier(table)

    Enum.each(columns, fn column ->
      column = quoted_identifier(column)

      execute("""
      ALTER TABLE #{schema}.#{table}
      ALTER COLUMN #{column} TYPE numeric(14, 2)
      USING round(#{column}::numeric, 2)
      """)
    end)
  end

  defp quoted_identifier(identifier) do
    "\"#{identifier |> to_string() |> String.replace("\"", "\"\"")}\""
  end
end
