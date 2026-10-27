defmodule TigooServer.Retaily.Sequence do
  use Ecto.Schema
  import Ecto.Changeset

  schema "app_sequence" do
    field :name, :string
    field :code, :string
    field :prefix, :string
    field :fill, :integer
    field :increment_by, :integer
    field :current_seq, :integer
  end

  def changeset(sequence, attrs) do
    sequence
    |> cast(attrs, [:name, :code, :prefix, :fill, :increment_by, :current_seq])
    |> validate_required([:name, :code, :prefix, :fill, :increment_by, :current_seq])
    |> validate_inclusion(:code, ["CF", "VF", "DV"] ++ TigooServer.Fe.TestInvoices.sequence_codes())
    |> validate_number(:fill, greater_than: 0)
    |> validate_number(:increment_by, greater_than: 0)
    |> validate_number(:current_seq, greater_than_or_equal_to: 0)
    |> unique_constraint(:code)
  end
end

defmodule TigooServer.Retaily.Sale do
  use Ecto.Schema

  import Ecto.Changeset

  schema "sale" do
    field :amount, :decimal
    field :sub, :decimal
    field :discount, :decimal
    field :discount_type, :string
    field :discount_input, :decimal
    field :tax_amount, :decimal
    field :delivery_charge, :decimal
    field :sequence, :string
    field :sequence_type, :string
    field :status, :string
    field :sale_type, :string
    field :date_create, :naive_datetime
    field :due_date, :date
    field :login, :string
    field :cancelled_by, :string
    field :additional_info, :string

    belongs_to :client, TigooServer.Retaily.Client, type: :integer
    belongs_to :store, TigooServer.Retaily.Store, type: :integer
    has_many :sale_lines, TigooServer.Retaily.SaleLine
    has_many :sale_paids, TigooServer.Retaily.SalePaid

    field :total_paid, :decimal, virtual: true
    field :due_balance, :decimal, virtual: true
    field :invoice_status, :string, virtual: true

    def changeset(sale, attrs) do
      sale
      |> cast(attrs, [
        :amount,
        :sub,
        :discount,
        :discount_type,
        :discount_input,
        :tax_amount,
        :delivery_charge,
        :sequence,
        :sequence_type,
        :status,
        :sale_type,
        :due_date,
        :login,
        :cancelled_by,
        :client_id,
        :store_id,
        :additional_info
      ])
      |> validate_required([
        :amount,
        :sub,
        :discount,
        :tax_amount,
        :sequence,
        :sequence_type,
        :status,
        :sale_type,
        :login,
        :client_id,
        :store_id
      ])
      |> update_change(:additional_info, &String.trim/1)
      |> validate_length(:additional_info, max: 1000)
      |> validate_inclusion(:discount_type, ["money", "percentage"])
      |> check_constraint(:discount_type, name: :sale_discount_type_valid)
    end
  end
end

defmodule TigooServer.Retaily.SaleLine do
  use Ecto.Schema

  import Ecto.Changeset

  schema "sale_line" do
    field :amount, :decimal
    field :tax_amount, :decimal
    field :discount, :decimal
    field :discount_type, :string
    field :discount_input, :decimal
    # Retaily's existing PostgreSQL migration stores sale quantities as float.
    field :quantity, :float
    field :price, :decimal, virtual: true
    field :total_amount, :decimal

    belongs_to :sale, TigooServer.Retaily.Sale, type: :integer
    belongs_to :product, TigooServer.Retaily.Product, type: :integer

    def changeset(line, attrs) do
      line
      |> cast(attrs, [
        :amount,
        :tax_amount,
        :discount,
        :discount_type,
        :discount_input,
        :quantity,
        :total_amount,
        :sale_id,
        :product_id
      ])
      |> validate_required([
        :amount,
        :tax_amount,
        :discount,
        :quantity,
        :total_amount,
        :sale_id,
        :product_id
      ])
      |> validate_inclusion(:discount_type, ["money", "percentage"])
      |> check_constraint(:discount_type, name: :sale_line_discount_type_valid)
    end
  end
end

defmodule TigooServer.Retaily.SalePaid do
  use Ecto.Schema

  import Ecto.Changeset

  schema "sale_paid" do
    field :amount, :decimal
    field :type, :string
    field :login, :string
    field :date_create, :naive_datetime
    belongs_to :sale, TigooServer.Retaily.Sale, type: :integer

    def changeset(payment, attrs) do
      payment
      |> cast(attrs, [:amount, :type, :login, :sale_id, :date_create])
      |> validate_required([:amount, :type, :sale_id])
      |> validate_inclusion(:type, ["CASH", "CC"])
      |> validate_number(:amount, greater_than: 0)
    end
  end
end
