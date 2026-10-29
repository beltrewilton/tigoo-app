defmodule TigooServer.FeReceivedApproval do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "fe_received_approvals" do
    field :issuer_rnc, :string
    field :buyer_rnc, :string
    field :encf, :string
    field :emission_date, :string
    field :amount, :decimal
    field :state, :string
    field :rejection_reason, :string
    field :approval_timestamp, :string
    field :xml, :string
    field :xml_sha256, :string
    field :certificate_sha256, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:issuer_rnc, :buyer_rnc, :encf, :emission_date, :amount,
      :state, :rejection_reason, :approval_timestamp, :xml, :xml_sha256, :certificate_sha256])
    |> validate_required([:issuer_rnc, :buyer_rnc, :encf, :emission_date, :amount,
      :state, :approval_timestamp, :xml, :xml_sha256, :certificate_sha256])
    |> validate_inclusion(:state, ["1", "2"])
    |> unique_constraint([:issuer_rnc, :buyer_rnc, :encf, :xml_sha256], name: :fe_received_approvals_document_index)
  end
end
