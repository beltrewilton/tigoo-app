defmodule TigooServer.Repo.Migrations.CreateCompany do
  use Ecto.Migration

  def change do
    create table(:company, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :rnc, :string
      add :company_name, :string
      add :access_token, :text
      add :active, :boolean, default: true, null: false
      add :connected, :boolean, default: false, null: false
      add :odoo_url, :string
      add :odoo_db, :string
      add :odoo_user, :string
      add :odoo_apikey, :string

      timestamps(type: :utc_datetime)
    end

    create index(:company, [:rnc])
    create index(:company, [:company_name])
    create index(:company, [:access_token])
  end
end
