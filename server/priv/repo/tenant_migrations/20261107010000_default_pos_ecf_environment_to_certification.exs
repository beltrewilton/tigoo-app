defmodule TigooServer.Repo.Migrations.DefaultPosEcfEnvironmentToCertification do
  use Ecto.Migration

  def up do
    alter table(:fe_test_invoices) do
      modify :environment, :string, default: "certecf", null: false
    end

    # Readiness previously covered testecf. Require reconciliation for CerteCF
    # without changing any counters or historical invoice environments.
    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""
    execute("UPDATE #{schema}.company SET ecf_test_sequences_ready = FALSE")
  end

  def down do
    alter table(:fe_test_invoices) do
      modify :environment, :string, default: "testecf", null: false
    end
  end
end
