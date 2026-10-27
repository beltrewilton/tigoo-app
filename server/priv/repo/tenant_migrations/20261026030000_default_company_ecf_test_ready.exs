defmodule TigooServer.Repo.Migrations.DefaultCompanyEcfTestReady do
  use Ecto.Migration

  def up do
    alter table(:company) do
      modify :ecf_test_sequences_ready, :boolean, null: false, default: true
    end

    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""
    execute "UPDATE #{schema}.company SET ecf_test_sequences_ready = TRUE WHERE ecf_test_sequences_ready = FALSE"
  end

  def down do
    alter table(:company) do
      modify :ecf_test_sequences_ready, :boolean, null: false, default: false
    end
  end
end
