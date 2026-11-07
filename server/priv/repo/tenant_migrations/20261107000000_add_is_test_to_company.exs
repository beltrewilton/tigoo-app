defmodule TigooServer.Repo.Migrations.AddIsTestToCompany do
  use Ecto.Migration

  def change do
    alter table(:company) do
      add :is_test, :boolean, default: false, null: false
    end
  end
end
