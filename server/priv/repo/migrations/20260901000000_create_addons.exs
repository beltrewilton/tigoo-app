defmodule TigooServer.Repo.Migrations.CreateAddons do
  use Ecto.Migration

  def change do
    create table(:addons, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :identifier, :string, null: false
      add :name, :string, null: false
      add :route, :string, null: false
      add :icon, :string, null: false
      add :handler, :string, null: false
      add :installed, :boolean, null: false, default: true
      add :enabled, :boolean, null: false, default: true
      add :installed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:addons, [:identifier])
    create unique_index(:addons, [:route])
    create index(:addons, [:enabled])
  end
end
