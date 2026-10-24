defmodule TigooServer.Repo.Migrations.AddDiscountTypesToSales do
  use Ecto.Migration

  def up do
    alter table(:sale) do
      add :discount_type, :string, size: 10
      # Keep the entered percentage so reports can faithfully render it after
      # `discount` has been normalized to its monetary deduction.
      add :discount_input, :decimal, precision: 14, scale: 2
    end

    alter table(:sale_line) do
      add :discount_type, :string, size: 10
      add :discount_input, :decimal, precision: 14, scale: 2
    end

    create constraint(:sale, :sale_discount_type_valid,
             check: "discount_type IS NULL OR discount_type IN ('money', 'percentage')"
           )

    create constraint(:sale_line, :sale_line_discount_type_valid,
             check: "discount_type IS NULL OR discount_type IN ('money', 'percentage')"
           )
  end

  def down do
    drop constraint(:sale_line, :sale_line_discount_type_valid)
    drop constraint(:sale, :sale_discount_type_valid)

    alter table(:sale_line) do
      remove :discount_input
      remove :discount_type
    end

    alter table(:sale) do
      remove :discount_input
      remove :discount_type
    end
  end
end
