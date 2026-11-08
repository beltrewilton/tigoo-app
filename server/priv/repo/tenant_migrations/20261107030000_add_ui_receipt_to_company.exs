defmodule TigooServer.Repo.Migrations.AddUiReceiptToCompany do
  use Ecto.Migration

  def change do
    alter table(:company) do
      add :ui_receipt, :boolean, default: false, null: false
    end
  end
end
