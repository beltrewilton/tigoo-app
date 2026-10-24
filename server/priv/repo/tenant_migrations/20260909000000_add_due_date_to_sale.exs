defmodule TigooServer.Repo.Migrations.AddDueDateToSale do
  use Ecto.Migration

  def change do
    alter table(:sale) do
      add :due_date, :date
    end
  end
end
