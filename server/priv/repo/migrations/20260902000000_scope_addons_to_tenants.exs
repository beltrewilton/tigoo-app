defmodule TigooServer.Repo.Migrations.ScopeAddonsToTenants do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:addons, [:identifier])
    drop_if_exists unique_index(:addons, [:route])

    alter table(:addons) do
      add :tenant, :string
      add :revision, :string
    end

    create unique_index(:addons, [:identifier, :tenant])
    create unique_index(:addons, [:route, :tenant])
    create index(:addons, [:tenant, :enabled])
  end

  def down do
    drop_if_exists index(:addons, [:tenant, :enabled])
    drop_if_exists unique_index(:addons, [:route, :tenant])
    drop_if_exists unique_index(:addons, [:identifier, :tenant])

    alter table(:addons) do
      remove :revision
      remove :tenant
    end

    create unique_index(:addons, [:identifier])
    create unique_index(:addons, [:route])
  end
end
