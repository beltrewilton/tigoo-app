defmodule TigooServer.Repo.Migrations.AddTimezoneOffsetToCompany do
  use Ecto.Migration

  def change do
    alter table(:company) do
      add :timezone_offset, :integer, default: -4, null: false
    end
  end
end
