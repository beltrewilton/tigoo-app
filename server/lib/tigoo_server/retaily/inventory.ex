defmodule TigooServer.Retaily.Store do
  use Ecto.Schema
  import Ecto.Changeset

  schema "app_store" do
    field :name, :string
    field :date_create, :naive_datetime
    field :company_id, :string
    field :slogan, :string
    field :logo, :string
    field :address, :string

    has_many :inventory_entries, TigooServer.Retaily.Inventory
    has_many :inventory_heads, TigooServer.Retaily.InventoryHead
    has_many :received_product_orders, TigooServer.Retaily.ProductOrder, foreign_key: :to_store_id
    has_many :product_order_lines, TigooServer.Retaily.ProductOrderLine, foreign_key: :to_store_id
    many_to_many :users, TigooServer.Retaily.User, join_through: TigooServer.Retaily.UserStore
  end

  def changeset(store, attrs) do
    store
    |> cast(attrs, [:name, :company_id, :slogan, :logo, :address, :date_create])
    |> validate_required([:name])
    |> validate_length(:name, max: 50)
    |> validate_length(:slogan, max: 120)
    |> validate_length(:address, max: 200)
    |> validate_length(:logo, max: 1_000_000)
    |> validate_format(:logo, ~r/^data:image\/[a-zA-Z0-9.+-]+;base64,/,
      message: "must be an image encoded as Base64"
    )
    |> unique_constraint(:name)
  end
end

defmodule TigooServer.Retaily.Inventory do
  use Ecto.Schema

  import Ecto.Changeset

  schema "app_inventory" do
    field :prev_quantity, :integer, default: 0
    field :quantity, :integer
    field :next_quantity, :integer, default: 0
    field :status, :string, default: "quiet"
    field :last_update, :naive_datetime
    field :user_updated, :string

    belongs_to :product, TigooServer.Retaily.Product
    belongs_to :store, TigooServer.Retaily.Store
  end

  def changeset(inventory, attrs) do
    inventory
    |> cast(attrs, [
      :prev_quantity,
      :quantity,
      :last_update,
      :user_updated,
      :product_id,
      :store_id
    ])
    |> validate_required([:quantity, :product_id, :store_id])
  end
end

defmodule TigooServer.Retaily.InventoryHead do
  use Ecto.Schema

  schema "app_inventory_head" do
    field :name, :string
    field :date_create, :naive_datetime
    field :date_close, :naive_datetime
    field :status, :integer, default: 0
    field :memo, :string

    belongs_to :store, TigooServer.Retaily.Store
  end
end

defmodule TigooServer.Retaily.ProductOrder do
  use Ecto.Schema

  import Ecto.Changeset

  schema "product_order" do
    field :name, :string
    field :memo, :string
    field :order_type, :string
    field :user_requester, :string
    field :user_receiver, :string
    field :date_opened, :naive_datetime
    field :date_closed, :naive_datetime
    field :from_origin_id, :integer
    field :status, :string, default: "opened"

    belongs_to :to_store, TigooServer.Retaily.Store
    has_many :lines, TigooServer.Retaily.ProductOrderLine
    has_many :bulk_order_lines, TigooServer.Retaily.BulkOrderLine
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :name,
      :memo,
      :order_type,
      :user_requester,
      :user_receiver,
      :date_opened,
      :date_closed,
      :from_origin_id,
      :to_store_id,
      :status
    ])
    |> validate_required([:order_type, :from_origin_id, :to_store_id])
    |> validate_number(:from_origin_id, greater_than: 0)
    |> validate_number(:to_store_id, greater_than: 0)
  end
end

defmodule TigooServer.Retaily.ProductOrderLine do
  use Ecto.Schema

  import Ecto.Changeset

  schema "product_order_line" do
    field :from_origin_id, :integer
    field :quantity, :integer
    field :quantity_observed, :integer
    field :status, :string, default: "pending"
    field :date_create, :naive_datetime
    field :user_receiver, :string
    field :receiver_last_update, :naive_datetime
    field :receiver_memo, :string

    belongs_to :product, TigooServer.Retaily.Product
    belongs_to :to_store, TigooServer.Retaily.Store
    belongs_to :product_order, TigooServer.Retaily.ProductOrder
  end

  def changeset(line, attrs) do
    line
    |> cast(attrs, [
      :product_id,
      :from_origin_id,
      :to_store_id,
      :product_order_id,
      :quantity,
      :quantity_observed,
      :status,
      :date_create,
      :user_receiver,
      :receiver_last_update,
      :receiver_memo
    ])
    |> validate_required([
      :product_id,
      :from_origin_id,
      :to_store_id,
      :product_order_id,
      :quantity
    ])
    |> validate_number(:product_id, greater_than: 0)
    |> validate_number(:from_origin_id, greater_than: 0)
    |> validate_number(:to_store_id, greater_than: 0)
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:quantity_observed, greater_than_or_equal_to: 0)
  end
end

defmodule TigooServer.Retaily.BulkOrder do
  use Ecto.Schema

  schema "bulk_order" do
    field :name, :string
    field :memo, :string
    field :date_create, :naive_datetime
    field :user_create, :string

    has_many :lines, TigooServer.Retaily.BulkOrderLine
  end
end

defmodule TigooServer.Retaily.BulkOrderLine do
  use Ecto.Schema

  schema "bulk_order_line" do
    belongs_to :bulk_order, TigooServer.Retaily.BulkOrder
    belongs_to :product_order, TigooServer.Retaily.ProductOrder
  end
end
