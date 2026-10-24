defmodule TigooServer.Repo.Migrations.FixAppInventoryLastUpdateLocalTimestamps do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE #{tenant_table(:app_inventory)}
    SET last_update = last_update - INTERVAL '4 hours'
    WHERE last_update IS NOT NULL
    """)
  end

  def down do
    execute("""
    UPDATE #{tenant_table(:app_inventory)}
    SET last_update = last_update + INTERVAL '4 hours'
    WHERE last_update IS NOT NULL
    """)
  end

  defp tenant_table(table) do
    "#{quoted_identifier(prefix() || "public")}.#{quoted_identifier(table)}"
  end

  defp quoted_identifier(identifier) do
    "\"#{identifier |> to_string() |> String.replace("\"", "\"\"")}\""
  end
end
