defmodule TigooServer.Repo.Migrations.AddLoginToSalePaid do
  use Ecto.Migration

  def change do
    alter table(:sale_paid) do
      add :login, :string
    end
  end
end
