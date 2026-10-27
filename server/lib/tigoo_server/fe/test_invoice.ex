defmodule TigooServer.Fe.TestInvoice do
  use Ecto.Schema

  schema "fe_test_invoices" do
    field :user_id, :integer
    field :store_id, :integer
    field :request_id, Ecto.UUID
    field :encf, :string
    field :environment, :string, default: "testecf"
    field :issuer_rnc, :string
    field :state, :string, default: "queued"
    field :snapshot, :map
    field :report, :map, default: %{}
    field :error, :string
    timestamps(type: :utc_datetime)
  end
end
