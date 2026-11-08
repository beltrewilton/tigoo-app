defmodule TigooServer.Repo.Migrations.RemoveCopiedIdentifierUniqueIndexes do
  use Ecto.Migration

  def up do
    # Copied tenant schemas use _idx names rather than Ecto's _index names.
    # The preceding migration already installs the ordinary search indexes.
    drop_if_exists index(:sale, [:sequence_type, :sequence],
      name: :sale_sequence_type_sequence_idx)
    drop_if_exists index(:fe_test_invoices, [:issuer_rnc, :environment, :encf],
      name: :fe_test_invoices_issuer_rnc_environment_encf_idx)
  end

  def down do
    # Identifier uniqueness is restored by the preceding migration's rollback.
    :ok
  end
end
