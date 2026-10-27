defmodule TigooServer.Repo.Migrations.AddPosEcfTest do
  use Ecto.Migration

  @types [
    {"31", "Crédito Fiscal Electrónico"}, {"32", "Consumo Electrónico"},
    {"33", "Nota de Débito Electrónica"}, {"34", "Nota de Crédito Electrónica"},
    {"41", "Compras Electrónico"}, {"43", "Gastos Menores Electrónico"},
    {"44", "Regímenes Especiales Electrónico"}, {"45", "Gubernamental Electrónico"},
    {"46", "Exportaciones Electrónico"}, {"47", "Pagos al Exterior Electrónico"}
  ]

  def up do
    alter table(:app_users) do
      add :ecf_test_enabled, :boolean, null: false, default: false
    end

    create table(:fe_test_invoices) do
      add :user_id, references(:app_users), null: false
      add :store_id, :bigint, null: false
      add :request_id, :uuid, null: false
      add :encf, :string, null: false
      add :environment, :string, null: false, default: "testecf"
      add :issuer_rnc, :string, null: false
      add :state, :string, null: false, default: "queued"
      add :snapshot, :map, null: false
      add :report, :map, null: false, default: %{}
      add :error, :text
      timestamps(type: :utc_datetime)
    end

    create unique_index(:fe_test_invoices, [:user_id, :request_id])
    create unique_index(:fe_test_invoices, [:issuer_rnc, :environment, :encf])
    create index(:fe_test_invoices, [:state])

    create table(:fe_test_mode_changes) do
      add :user_id, references(:app_users), null: false
      add :actor, :string, null: false
      add :enabled, :boolean, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create table(:fe_test_submission_attempts) do
      add :invoice_id, references(:fe_test_invoices), null: false
      add :state, :string, null: false
      add :report, :map, null: false
      add :error, :text
      timestamps(type: :utc_datetime, updated_at: false)
    end
    create index(:fe_test_submission_attempts, [:invoice_id])

    flush()
    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""
    for {type, name} <- @types do
      execute """
      INSERT INTO #{schema}.app_sequence (name, code, prefix, fill, increment_by, current_seq)
      SELECT '#{name}', 'TEST_E#{type}', 'E#{type}', 10, 1, 0
      WHERE NOT EXISTS (SELECT 1 FROM #{schema}.app_sequence WHERE code = 'TEST_E#{type}')
      """
    end
  end

  def down do
    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""
    execute "DELETE FROM #{schema}.app_sequence WHERE code IN ('TEST_E31','TEST_E32','TEST_E33','TEST_E34','TEST_E41','TEST_E43','TEST_E44','TEST_E45','TEST_E46','TEST_E47')"
    drop table(:fe_test_submission_attempts)
    drop table(:fe_test_mode_changes)
    drop table(:fe_test_invoices)
    alter table(:app_users), do: remove(:ecf_test_enabled)
  end
end
