defmodule TigooServer.Repo.Migrations.AddEcfProductionMode do
  use Ecto.Migration

  def change do
    alter table(:app_users) do
      add :ecf_production_enabled, :boolean, null: false, default: false
    end

    create constraint(:app_users, :exclusive_ecf_environment,
      check: "NOT (ecf_test_enabled AND ecf_production_enabled)")

    alter table(:fe_test_mode_changes) do
      add :production_enabled, :boolean, null: false, default: false
    end

    alter table(:company) do
      add :ecf_sequence_expiry, :date
    end
  end
end
