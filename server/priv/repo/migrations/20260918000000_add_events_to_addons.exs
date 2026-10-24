defmodule TigooServer.Repo.Migrations.AddEventsToAddons do
  use Ecto.Migration

  def change do
    alter table(:addons) do
      add :events, {:array, :string}, null: false, default: []
    end
  end
end
