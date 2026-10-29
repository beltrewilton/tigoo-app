defmodule TigooServer.Repo.Migrations.CreateFeReceivedApprovals do
  use Ecto.Migration

  def change do
    create table(:fe_received_approvals) do
      add :issuer_rnc, :string, null: false
      add :buyer_rnc, :string, null: false
      add :encf, :string, null: false
      add :emission_date, :string, null: false
      add :amount, :decimal, precision: 18, scale: 2, null: false
      add :state, :string, null: false
      add :rejection_reason, :text
      add :approval_timestamp, :string, null: false
      add :xml, :text, null: false
      add :xml_sha256, :string, size: 64, null: false
      add :certificate_sha256, :string, size: 64, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:fe_received_approvals, [:issuer_rnc, :buyer_rnc, :encf, :xml_sha256],
      name: :fe_received_approvals_document_index)
  end
end
