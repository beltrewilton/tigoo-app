defmodule TigooServer.Repo.Migrations.AddCancelledByToSale do
  use Ecto.Migration

  def change do
    alter table(:sale) do
      add :cancelled_by, :string, size: 45
    end
  end
end
