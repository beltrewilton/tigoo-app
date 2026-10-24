defmodule TigooServer.Retaily.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "product" do
    field :name, :string
    field :cost, :float
    field :margin, :float
    field :code, :string
    field :img_path, :string
    field :date_create, :naive_datetime
    field :image_raw, :string
    field :image_updated_at, :naive_datetime
    field :active, :integer
    field :user_modified, :string
    field :archived, :string, default: "0"

    has_many :inventory_entries, TigooServer.Retaily.Inventory
    has_many :pricing_entries, TigooServer.Retaily.PricingList
    has_many :order_lines, TigooServer.Retaily.ProductOrderLine
  end

  def changeset(product, attrs) do
    product
    |> cast(attrs, [
      :name,
      :cost,
      :margin,
      :code,
      :img_path,
      :image_raw,
      :image_updated_at,
      :active,
      :user_modified,
      :date_create,
      :archived
    ])
    |> validate_required([:name])
    |> validate_number(:cost, greater_than_or_equal_to: 0)
  end
end

defmodule TigooServer.Retaily.ProductBackup do
  use Ecto.Schema

  schema "product_bck" do
    field :name, :string
    field :cost, :float
    field :price, :float
    field :margin, :float
    field :code, :string
    field :img_path, :string
    field :date_create, :naive_datetime
    field :image_raw, :string
    field :active, :integer
    field :user_modified, :string
  end
end

defmodule TigooServer.Retaily.Pricing do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pricing" do
    field :label, :string
    field :user_modified, :string
    field :date_create, :naive_datetime
    field :price_key, :string
    field :status, :integer, default: 1

    has_many :entries, TigooServer.Retaily.PricingList
  end

  def changeset(pricing, attrs) do
    pricing
    |> cast(attrs, [:label, :price_key, :user_modified, :date_create, :status])
    |> validate_required([:label, :price_key])
    |> validate_length(:label, max: 90)
    |> validate_length(:price_key, max: 45)
    |> unique_constraint(:label)
    |> unique_constraint(:price_key)
  end
end

defmodule TigooServer.Retaily.PricingList do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pricing_list" do
    field :price, :float
    field :user_modified, :string
    field :date_create, :naive_datetime

    belongs_to :product, TigooServer.Retaily.Product
    belongs_to :pricing, TigooServer.Retaily.Pricing
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:price, :user_modified, :date_create, :product_id, :pricing_id])
    |> validate_required([:price, :product_id, :pricing_id])
    |> validate_number(:price, greater_than_or_equal_to: 0)
  end
end

defmodule TigooServer.Retaily.Provider do
  use Ecto.Schema
  import Ecto.Changeset

  schema "provider" do
    field :name, :string
    field :date_create, :naive_datetime
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :date_create])
    |> validate_required([:name])
    |> validate_length(:name, max: 50)
    |> unique_constraint(:name)
  end
end

defmodule TigooServer.Retaily.Delivery do
  use Ecto.Schema

  schema "delivery" do
    field :name, :string
    field :value, :float
  end
end

defmodule TigooServer.Retaily.Client do
  use Ecto.Schema

  import Ecto.Changeset
  alias TigooServer.Retaily.BusinessTime

  schema "client" do
    field :name, :string
    field :document_id, :string
    field :address, :string
    field :celphone, :string
    field :email, :string
    field :date_create, :naive_datetime
    field :wholesaler, :integer
  end

  def changeset(client, attrs) do
    client
    |> cast(attrs, [:name, :document_id, :address, :celphone, :email, :wholesaler])
    |> validate_required([:name])
    |> default_created_at(client)
  end

  defp default_created_at(changeset, %{id: nil}) do
    if get_field(changeset, :date_create),
      do: changeset,
      else: put_change(changeset, :date_create, BusinessTime.local_now())
  end

  defp default_created_at(changeset, _client), do: changeset
end
