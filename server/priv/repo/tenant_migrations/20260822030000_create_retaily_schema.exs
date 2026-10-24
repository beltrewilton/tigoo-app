defmodule TigooServer.Repo.Migrations.CreateRetailySchema do
  use Ecto.Migration

  def change do
    create table(:app_store) do
      add :name, :string, size: 50
      add :date_create, :naive_datetime, default: fragment("CURRENT_TIMESTAMP")
      add :company_id, :string, size: 50
      add :slogan, :string, size: 150
      add :logo, :text
      add :address, :string, size: 200
    end

    create unique_index(:app_store, [:name])

    create table(:app_users) do
      add :username, :string, size: 20
      add :password, :string, size: 200
      add :first_name, :string, size: 20
      add :last_name, :string, size: 30
      add :is_active, :integer
      add :date_joined, :naive_datetime
      add :last_login, :naive_datetime
      add :pic, :text
    end

    create unique_index(:app_users, [:username])

    create table(:app_user_store, primary_key: false) do
      add :user_id, references(:app_users), primary_key: true
      add :store_id, references(:app_store), primary_key: true
    end

    create index(:app_user_store, [:store_id])

    create table(:app_sequence, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :name, :string
      add :code, :string, size: 10
      add :prefix, :string, size: 10
      add :fill, :integer
      add :increment_by, :integer
      add :current_seq, :bigint
    end

    create table(:bulk_order) do
      add :name, :string, size: 45
      add :memo, :string, size: 500
      add :date_create, :naive_datetime, default: fragment("CURRENT_TIMESTAMP")
      add :user_create, :string, size: 45
    end

    create table(:client, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :name, :string
      add :document_id, :string, size: 30
      add :address, :string
      add :celphone, :string, size: 100
      add :email, :string, size: 100
      add :date_create, :naive_datetime, default: fragment("CURRENT_TIMESTAMP")
      add :wholesaler, :integer
    end

    create table(:delivery) do
      add :name, :string, size: 45
      add :value, :float
    end

    create table(:pricing) do
      add :label, :string, size: 90, null: false
      add :user_modified, :string, size: 90
      add :date_create, :naive_datetime, default: fragment("CURRENT_TIMESTAMP")
      add :price_key, :string, size: 45, null: false
      add :status, :integer, default: 1
    end

    create unique_index(:pricing, [:label])
    create unique_index(:pricing, [:price_key])

    create table(:product, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :name, :string
      add :cost, :float
      add :price, :float
      add :margin, :float
      add :code, :string, size: 45
      add :img_path, :string
      add :date_create, :naive_datetime
      add :image_raw, :text
      add :active, :integer
      add :user_modified, :string, size: 45
      add :archived, :string, size: 1, default: "0"
    end

    create table(:product_bck, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :name, :string
      add :cost, :float
      add :price, :float
      add :margin, :float
      add :code, :string, size: 45
      add :img_path, :string
      add :date_create, :naive_datetime
      add :image_raw, :text
      add :active, :integer
      add :user_modified, :string, size: 45
    end

    create table(:app_inventory) do
      add :prev_quantity, :integer, default: 0
      add :quantity, :integer
      add :next_quantity, :integer, default: 0
      add :status, :string, size: 10, default: "quiet"
      add :last_update, :naive_datetime
      add :user_updated, :string, size: 90
      add :product_id, references(:product, type: :bigint)
      add :store_id, references(:app_store)
    end

    create index(:app_inventory, [:product_id])
    create index(:app_inventory, [:store_id])

    create table(:app_inventory_head) do
      add :name, :string, size: 90
      add :date_create, :naive_datetime, default: fragment("CURRENT_TIMESTAMP")
      add :date_close, :naive_datetime
      add :status, :integer, default: 0
      add :memo, :string, size: 500
      add :store_id, references(:app_store)
    end

    create index(:app_inventory_head, [:store_id])

    create table(:pricing_list) do
      add :price, :float
      add :user_modified, :string, size: 90
      add :date_create, :naive_datetime, default: fragment("CURRENT_TIMESTAMP")
      add :product_id, references(:product, type: :bigint)
      add :pricing_id, references(:pricing)
    end

    create index(:pricing_list, [:product_id])
    create index(:pricing_list, [:pricing_id])

    create table(:product_order) do
      add :name, :string, size: 90
      add :memo, :string, size: 500
      add :order_type, :string, size: 45
      add :user_requester, :string, size: 45
      add :user_receiver, :string, size: 45
      add :date_opened, :naive_datetime, default: fragment("CURRENT_TIMESTAMP")
      add :date_closed, :naive_datetime
      add :from_origin_id, :integer
      add :to_store_id, references(:app_store)
      add :status, :string, size: 45, default: "opened"
    end

    create index(:product_order, [:to_store_id])

    create table(:product_order_line) do
      add :product_id, references(:product, type: :bigint)
      add :from_origin_id, :integer
      add :to_store_id, references(:app_store)
      add :product_order_id, references(:product_order)
      add :quantity, :integer
      add :quantity_observed, :integer
      add :status, :string, size: 10, default: "pending"
      add :date_create, :naive_datetime, default: fragment("CURRENT_TIMESTAMP")
      add :user_receiver, :string, size: 45
      add :receiver_last_update, :naive_datetime
      add :receiver_memo, :string, size: 500
    end

    create index(:product_order_line, [:product_id])
    create index(:product_order_line, [:to_store_id])
    create index(:product_order_line, [:product_order_id])

    create table(:bulk_order_line) do
      add :bulk_order_id, references(:bulk_order)
      add :product_order_id, references(:product_order)
    end

    create index(:bulk_order_line, [:bulk_order_id])
    create index(:bulk_order_line, [:product_order_id])

    create table(:provider) do
      add :name, :string, size: 50
      add :date_create, :naive_datetime, default: fragment("CURRENT_TIMESTAMP")
    end

    create unique_index(:provider, [:name])

    create table(:sale, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :amount, :float
      add :sub, :float
      add :discount, :float
      add :tax_amount, :float
      add :delivery_charge, :float
      add :sequence, :string, size: 30
      add :sequence_type, :string, size: 45
      add :status, :string, size: 45
      add :sale_type, :string, size: 45
      add :date_create, :naive_datetime, default: fragment("CURRENT_TIMESTAMP")
      add :login, :string, size: 45
      add :client_id, :bigint, default: 0, null: false
      add :store_id, :bigint, default: 0, null: false
      add :additional_info, :string, size: 1000
    end

    create index(:sale, [:store_id, :date_create])
    create index(:sale, [:store_id, :client_id, :date_create])

    create table(:sale_line, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :amount, :float
      add :tax_amount, :float
      add :discount, :float
      add :quantity, :float
      add :total_amount, :float
      add :sale_id, :bigint, default: 0, null: false
      add :product_id, :bigint
    end

    create table(:sale_paid, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :amount, :float
      add :type, :string, size: 10
      add :date_create, :naive_datetime
      add :sale_id, :bigint, default: 0, null: false
    end

    create table(:scope_list) do
      add :name, :string, size: 200
    end

    tenant_prefix = prefix()

    execute(
      """
      INSERT INTO #{tenant_prefix}.scope_list (name) VALUES
        ('cx'),
        ('sales'),
        ('human'),
        ('dashboard.view'),
        ('sales.pos'),
        ('sales.view'),
        ('inventory.view'),
        ('inventory.stores'),
        ('inventory.bulk'),
        ('inventory.movement.request'),
        ('inventory.movement.response'),
        ('inventory.purchase.request'),
        ('inventory.purchase.response'),
        ('user.view'),
        ('user.setting'),
        ('company.settings'),
        ('report.view'),
        ('analityc.view'),
        ('product.add'),
        ('product.view'),
        ('product.pricelist'),
        ('product.view.cost'),
        ('sales.filter.user'),
        ('sales.filter.store'),
        ('product.view.edit'),
        ('product.edit'),
        ('product.view.active_column'),
        ('pos.delivery')
      """,
      "DELETE FROM #{tenant_prefix}.scope_list"
    )

    create table(:scopes) do
      add :name, :string, size: 50
      add :user_id, references(:app_users)
    end

    create index(:scopes, [:user_id])
  end
end
