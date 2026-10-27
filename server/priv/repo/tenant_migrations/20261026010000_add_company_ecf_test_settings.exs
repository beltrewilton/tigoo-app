defmodule TigooServer.Repo.Migrations.AddCompanyEcfTestSettings do
  use Ecto.Migration

  def change do
    alter table(:company) do
      add_if_not_exists :address, :string
      add :ecf_test_sequence_expiry, :date
      add :ecf_test_sequences_ready, :boolean, null: false, default: false
    end
  end
end
