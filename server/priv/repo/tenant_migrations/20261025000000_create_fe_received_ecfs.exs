defmodule TigooServer.Repo.Migrations.CreateFeReceivedEcfs do
  use Ecto.Migration

  def change do
    create table(:fe_received_ecfs) do
      add :issuer_rnc, :string, null: false
      add :buyer_rnc, :string, null: false
      add :encf, :string, null: false
      add :type, :string, null: false
      add :xml, :text, null: false
      add :receipt_xml, :text, null: false
      add :certificate_sha256, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:fe_received_ecfs, [:issuer_rnc, :encf])
  end
end
