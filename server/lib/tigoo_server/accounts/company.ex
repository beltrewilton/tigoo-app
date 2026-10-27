defmodule TigooServer.Accounts.Company do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "company" do
    field :rnc, :string
    field :company_name, :string
    field :address, :string, default: "AVE ITALIA 54"
    field :ecf_test_sequence_expiry, :date, default: ~D[2028-12-31]
    field :ecf_test_sequences_ready, :boolean, default: true
    field :access_token, :string
    field :active, :boolean, default: true
    field :connected, :boolean, default: false
    field :odoo_url, :string
    field :odoo_db, :string
    field :odoo_user, :string
    field :odoo_apikey, :string
    field :brand_logo, :string
    field :timezone_offset, :integer, default: -4

    timestamps(type: :utc_datetime)
  end

  def changeset(company, attrs) do
    company
    |> cast(attrs, [:company_name, :rnc, :brand_logo, :timezone_offset])
    |> validate_required([:company_name])
    |> validate_number(:timezone_offset, greater_than_or_equal_to: -12, less_than_or_equal_to: 14)
    |> validate_format(:brand_logo, ~r/^data:image\/[a-zA-Z0-9.+-]+;base64,/,
      message: "must be an image encoded as Base64"
    )
  end
end
