defmodule TigooServer.Retaily.OrderRequests.Line do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :product_id, :integer
    field :from_origin_id, :integer
    field :quantity, :integer
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [:product_id, :from_origin_id, :quantity])
    |> validate_required([:product_id, :quantity])
    |> validate_number(:product_id, greater_than: 0)
    |> validate_number(:from_origin_id, greater_than: 0)
    |> validate_number(:quantity, greater_than: 0)
  end
end

defmodule TigooServer.Retaily.OrderRequests.Create do
  use Ecto.Schema

  import Ecto.Changeset

  alias TigooServer.Retaily.OrderRequests.Line

  @primary_key false
  embedded_schema do
    field :name, :string
    field :memo, :string
    field :order_type, :string
    field :from_origin_id, :integer
    field :to_store_id, :integer
    embeds_many :lines, Line
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [:name, :memo, :order_type, :from_origin_id, :to_store_id])
    |> cast_embed(:lines, required: true)
    |> validate_required([:order_type, :from_origin_id, :to_store_id])
    |> validate_length(:lines, min: 1)
    |> validate_number(:from_origin_id, greater_than: 0)
    |> validate_number(:to_store_id, greater_than: 0)
  end
end

defmodule TigooServer.Retaily.OrderRequests.ReceiptLine do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :id, :integer
    field :quantity_observed, :integer
    field :receiver_memo, :string
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [:id, :quantity_observed, :receiver_memo])
    |> validate_required([:id])
    |> validate_number(:id, greater_than: 0)
    |> validate_number(:quantity_observed, greater_than_or_equal_to: 0)
  end
end

defmodule TigooServer.Retaily.OrderRequests.Receive do
  use Ecto.Schema

  import Ecto.Changeset

  alias TigooServer.Retaily.OrderRequests.ReceiptLine

  @primary_key false
  embedded_schema do
    field :receiver_memo, :string
    embeds_many :lines, ReceiptLine
  end

  def changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [:receiver_memo])
    |> cast_embed(:lines)
  end
end
