defmodule TigooServer.Repo.Migrations.CreateTigooSchema do
  use Ecto.Migration

  @obsolete_permissions ~w(
    analityc.view
    cx
    human
    inventory.bulk
    inventory.movement.request
    inventory.movement.response
    inventory.purchase.request
    inventory.purchase.response
    inventory.stores
    product.pricelist
    product.view.active_column
    product.view.edit
    report.view
    sales
    sales.filter.store
    sales.filter.user
    user.setting
  )

  @permissions ~w(
    company.settings
    dashboard.view
    inventory.view
    pos.addons
    pos.addons.install
    pos.customer
    pos.delivery
    pos.orders
    pos.reconciliation
    product.add
    product.edit
    product.view
    product.view.cost
    sales.pos
    sales.view
    user.view
  )

  @new_permissions ~w(
    pos.addons
    pos.addons.install
    pos.customer
    pos.orders
    pos.reconciliation
  )

  def up do
    tenant_prefix = prefix()

    execute("""
    DELETE FROM #{tenant_prefix}.scopes
    WHERE name IN (#{quoted(@obsolete_permissions)})
    """)

    execute("""
    DELETE FROM #{tenant_prefix}.scope_list
    WHERE name IN (#{quoted(@obsolete_permissions)})
    """)

    Enum.each(@permissions, fn permission ->
      execute("""
      INSERT INTO #{tenant_prefix}.scope_list (name)
      SELECT '#{permission}'
      WHERE NOT EXISTS (
        SELECT 1 FROM #{tenant_prefix}.scope_list WHERE name = '#{permission}'
      )
      """)
    end)
  end

  def down do
    tenant_prefix = prefix()

    execute("""
    DELETE FROM #{tenant_prefix}.scope_list
    WHERE name IN (#{quoted(@new_permissions)})
    """)
  end

  defp quoted(permissions), do: Enum.map_join(permissions, ", ", &"'#{&1}'")
end
