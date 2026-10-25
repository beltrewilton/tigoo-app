defmodule TigooServer.FeReceivedEcf do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "fe_received_ecfs" do
    field :issuer_rnc, :string
    field :buyer_rnc, :string
    field :encf, :string
    field :type, :string
    field :xml, :string
    field :receipt_xml, :string
    field :certificate_sha256, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:issuer_rnc, :buyer_rnc, :encf, :type, :xml, :receipt_xml, :certificate_sha256])
    |> validate_required([:issuer_rnc, :buyer_rnc, :encf, :type, :xml, :receipt_xml, :certificate_sha256])
    |> unique_constraint([:issuer_rnc, :encf])
  end
end
