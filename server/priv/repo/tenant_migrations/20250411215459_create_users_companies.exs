defmodule TigooServer.Repo.Migrations.CreateUsersCompaniesJoinTable do
  use Ecto.Migration

  def change do
    create table(:users_companies, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all, prefix: "public")
      add :company_id, references(:company, type: :binary_id, on_delete: :delete_all)
    end

    create unique_index(:users_companies, [:user_id, :company_id])
  end
end
