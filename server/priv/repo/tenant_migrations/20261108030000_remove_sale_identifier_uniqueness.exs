defmodule TigooServer.Repo.Migrations.RemoveSaleIdentifierUniqueness do
  use Ecto.Migration

  def up do
    # Replace identifier uniqueness with ordinary indexes.
    # Keep ordinary indexes for searches without rejecting repeated identifiers.
    drop_if_exists index(:sale, [:sequence_type, :sequence])
    create index(:sale, [:sequence_type, :sequence])

    drop_if_exists index(:fe_test_invoices, [:issuer_rnc, :environment, :encf])
    create index(:fe_test_invoices, [:issuer_rnc, :environment, :encf])
  end

  def down do
    # This fails atomically if duplicates need reconciliation first.
    drop index(:sale, [:sequence_type, :sequence])
    create unique_index(:sale, [:sequence_type, :sequence])

    drop index(:fe_test_invoices, [:issuer_rnc, :environment, :encf])
    create unique_index(:fe_test_invoices, [:issuer_rnc, :environment, :encf])
  end
end
