defmodule TigooServer.Repo.Migrations.AddBrandLogoToCompany do
  use Ecto.Migration

  def change do
    alter table(:company) do
      add :brand_logo, :text
    end
  end
end
