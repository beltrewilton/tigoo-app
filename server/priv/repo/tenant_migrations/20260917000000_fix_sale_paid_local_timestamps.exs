defmodule TigooServer.Repo.Migrations.FixSalePaidLocalTimestamps do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE #{tenant_table(:sale_paid)}
    SET date_create = date_create - INTERVAL '4 hours'
    WHERE date_create IS NOT NULL
    """)
  end

  def down do
    execute("""
    UPDATE #{tenant_table(:sale_paid)}
    SET date_create = date_create + INTERVAL '4 hours'
    WHERE date_create IS NOT NULL
    """)
  end

  defp tenant_table(table) do
    "#{quoted_identifier(prefix() || "public")}.#{quoted_identifier(table)}"
  end

  defp quoted_identifier(identifier) do
    "\"#{identifier |> to_string() |> String.replace("\"", "\"\"")}\""
  end
end
