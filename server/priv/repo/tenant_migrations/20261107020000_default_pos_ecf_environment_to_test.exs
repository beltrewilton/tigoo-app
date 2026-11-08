defmodule TigooServer.Repo.Migrations.DefaultPosEcfEnvironmentToTest do
  use Ecto.Migration

  def up do
    alter table(:fe_test_invoices) do
      modify :environment, :string, default: "testecf", null: false
    end
  end

  def down do
    alter table(:fe_test_invoices) do
      modify :environment, :string, default: "certecf", null: false
    end
  end
end
