defmodule TigooServer.Retaily.SaleRequests.Line do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :product_id, :integer
    field :quantity, :integer
    field :ecf_tax, :string, default: "1"
    field :ecf_kind, :string, default: "1"
    field :discount, :decimal, default: Decimal.new(0)
    field :discount_type, :string, default: "money"
    field :discount_input, :decimal
  end

  def changeset(line, attrs, ecf_test? \\ false) do
    fields = [:product_id, :quantity, :discount, :discount_type, :discount_input]
    fields = if ecf_test?, do: fields ++ [:ecf_tax, :ecf_kind], else: fields
    line
    |> cast(attrs, fields)
    |> validate_required([:product_id, :quantity, :discount])
    |> validate_ecf_line(ecf_test?)
    |> validate_number(:product_id, greater_than: 0)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:discount, greater_than_or_equal_to: 0)
    |> validate_inclusion(:discount_type, ["money", "percentage"])
    |> validate_percentage_input()
  end

  defp validate_ecf_line(changeset, false), do: changeset
  defp validate_ecf_line(changeset, true) do
    changeset |> validate_inclusion(:ecf_tax, ~w(1 2 3 4)) |> validate_inclusion(:ecf_kind, ~w(1 2))
  end

  defp validate_percentage_input(changeset) do
    if get_field(changeset, :discount_type) == "percentage" do
      changeset
      |> validate_required(:discount_input)
      |> validate_number(:discount_input, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    else
      changeset
    end
  end
end

defmodule TigooServer.Retaily.SaleRequests.Payment do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :amount, :decimal
    field :type, :string
  end

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [:amount, :type])
    |> validate_required([:amount, :type])
    |> validate_inclusion(:type, ["CASH", "CC"])
    |> validate_number(:amount, greater_than: 0)
  end
end

defmodule TigooServer.Retaily.SaleRequests.Checkout do
  use Ecto.Schema

  import Ecto.Changeset

  alias TigooServer.Retaily.SaleRequests.{Line, Payment}

  @primary_key false
  embedded_schema do
    field :store_id, :integer
    field :client_id, :integer
    field :sequence_type, :string
    field :status, :string
    field :sale_type, :string
    field :due_date, :date
    field :delivery_charge, :decimal, default: Decimal.new(0)
    field :discount, :decimal, default: Decimal.new(0)
    field :discount_type, :string
    field :discount_input, :decimal
    field :additional_info, :string, default: ""
    field :ecf_buyer_kind, :string, default: "domestic"
    field :ecf_buyer_id, :string
    field :ecf_buyer_name, :string
    field :ecf_buyer_address, :string
    field :ecf_buyer_country, :string
    field :ecf_destination_country, :string
    field :ecf_income_type, :string, default: "01"
    field :ecf_buyer_confirmed, :boolean, default: false
    field :ecf_export_confirmed, :boolean, default: false
    embeds_many :lines, Line
    embeds_many :payments, Payment
  end

  def changeset(checkout, attrs, sequence_codes \\ ["CF", "VF", "DV"]) do
    ecf_test? = Enum.any?(sequence_codes, &String.starts_with?(&1, "TEST_E"))
    fields = [:store_id, :client_id, :sequence_type, :status, :sale_type, :due_date,
      :delivery_charge, :discount, :discount_type, :discount_input, :additional_info]
    fields = if ecf_test?, do: fields ++ [:ecf_buyer_kind, :ecf_buyer_id, :ecf_buyer_name,
      :ecf_buyer_address, :ecf_buyer_country, :ecf_destination_country, :ecf_income_type,
      :ecf_buyer_confirmed, :ecf_export_confirmed], else: fields
    checkout
    |> cast(attrs, fields)
    |> update_change(:additional_info, &String.trim/1)
    |> cast_embed(:lines, required: true, with: fn line, params -> Line.changeset(line, params, ecf_test?) end)
    |> cast_embed(:payments)
    |> validate_required([
      :store_id,
      :client_id,
      :sequence_type,
      :status,
      :sale_type,
      :delivery_charge
    ])
    |> validate_number(:store_id, greater_than: 0)
    |> validate_number(:client_id, greater_than: 0)
    |> validate_number(:delivery_charge, greater_than_or_equal_to: 0)
    |> validate_number(:discount, greater_than_or_equal_to: 0)
    |> validate_length(:additional_info, max: 1000)
    |> validate_inclusion(:discount_type, ["money", "percentage"])
    |> validate_percentage_input()
    |> validate_inclusion(:sequence_type, sequence_codes)
    |> validate_inclusion(:status, ["CASH", "CREDIT"])
    |> validate_inclusion(:sale_type, ["IN_SHOP", "FOR_DELIVER"])
    |> validate_credit_payments()
    |> validate_credit_due_date()
    |> validate_ecf_details(ecf_test?)
  end

  defp validate_ecf_details(changeset, false), do: changeset
  defp validate_ecf_details(changeset, true) do
    code = get_field(changeset, :sequence_type)
    if code in TigooServer.Fe.SaleFiscal.codes() do
      changeset = Enum.reduce([:ecf_buyer_id, :ecf_buyer_name, :ecf_buyer_address, :ecf_buyer_country, :ecf_destination_country],
        changeset, fn field, acc -> update_change(acc, field, &String.trim/1) end)
      changeset = changeset
        |> validate_inclusion(:ecf_buyer_kind, ~w(domestic foreign))
        |> validate_inclusion(:ecf_income_type, ~w(01 02 03 04 05 06))
        |> validate_length(:ecf_buyer_id, max: 20)
        |> validate_length(:ecf_buyer_name, max: 150)
        |> validate_length(:ecf_buyer_address, max: 100)
        |> validate_length(:ecf_buyer_country, max: 60)
        |> validate_length(:ecf_destination_country, max: 60)
      changeset = if code in ~w(TEST_E31 TEST_E45) and get_field(changeset, :ecf_buyer_kind) == "foreign",
        do: add_error(changeset, :ecf_buyer_kind, "requires a domestic buyer RNC/cédula"), else: changeset
      changeset = if code in ~w(TEST_E44 TEST_E45),
        do: validate_acceptance(changeset, :ecf_buyer_confirmed, message: "confirm buyer eligibility"), else: changeset
      if code == "TEST_E46" do
        changeset
        |> validate_required([:ecf_buyer_country, :ecf_destination_country])
        |> validate_acceptance(:ecf_export_confirmed, message: "confirm export eligibility")
        |> validate_number(:delivery_charge, equal_to: 0, message: "separate delivery services must be invoiced separately from exported goods")
      else
        changeset
      end
    else
      changeset
    end
  end

  defp validate_percentage_input(changeset) do
    if get_field(changeset, :discount_type) == "percentage" do
      changeset
      |> validate_required(:discount_input)
      |> validate_number(:discount_input, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    else
      changeset
    end
  end

  defp validate_credit_payments(changeset) do
    if get_field(changeset, :status) == "CREDIT" and get_field(changeset, :payments) != [] do
      add_error(changeset, :payments, "must be empty for credit sales")
    else
      changeset
    end
  end

  defp validate_credit_due_date(changeset) do
    if get_field(changeset, :status) == "CREDIT" do
      changeset
      |> validate_required(:due_date)
      |> validate_change(:due_date, fn :due_date, due_date ->
        if Date.compare(due_date, Date.utc_today()) == :gt do
          []
        else
          [due_date: "must be a future date"]
        end
      end)
    else
      changeset
    end
  end
end
