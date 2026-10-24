defmodule TigooServer.Repo.Migrations.FixRetailyLocalBusinessTimestamps do
  use Ecto.Migration

  def up do
    shift("-")
  end

  def down do
    shift("+")
  end

  defp shift(operator) do
    execute("""
    UPDATE #{tenant_table(:app_users)}
    SET
      date_joined = CASE
        WHEN date_joined IS NULL THEN NULL
        ELSE date_joined #{operator} INTERVAL '4 hours'
      END,
      last_login = CASE
        WHEN last_login IS NULL THEN NULL
        ELSE last_login #{operator} INTERVAL '4 hours'
      END
    WHERE date_joined IS NOT NULL
       OR last_login IS NOT NULL
    """)

    execute("""
    UPDATE #{tenant_table(:product)}
    SET date_create = date_create #{operator} INTERVAL '4 hours'
    WHERE date_create IS NOT NULL
    """)

    execute("""
    UPDATE #{tenant_table(:product_traces)}
    SET inserted_at = inserted_at #{operator} INTERVAL '4 hours'
    WHERE inserted_at IS NOT NULL
    """)

    execute("""
    UPDATE #{tenant_table(:client)}
    SET date_create = date_create #{operator} INTERVAL '4 hours'
    WHERE date_create IS NOT NULL
    """)

    execute("""
    UPDATE #{tenant_table(:product_order)}
    SET
      date_opened = CASE
        WHEN date_opened IS NULL THEN NULL
        ELSE date_opened #{operator} INTERVAL '4 hours'
      END,
      date_closed = CASE
        WHEN date_closed IS NULL THEN NULL
        ELSE date_closed #{operator} INTERVAL '4 hours'
      END
    WHERE date_opened IS NOT NULL
       OR date_closed IS NOT NULL
    """)

    execute("""
    UPDATE #{tenant_table(:product_order_line)}
    SET
      date_create = CASE
        WHEN date_create IS NULL THEN NULL
        ELSE date_create #{operator} INTERVAL '4 hours'
      END,
      receiver_last_update = CASE
        WHEN receiver_last_update IS NULL THEN NULL
        ELSE receiver_last_update #{operator} INTERVAL '4 hours'
      END
    WHERE date_create IS NOT NULL
       OR receiver_last_update IS NOT NULL
    """)
  end

  defp tenant_table(table) do
    "#{quoted_identifier(prefix() || "public")}.#{quoted_identifier(table)}"
  end

  defp quoted_identifier(identifier) do
    "\"#{identifier |> to_string() |> String.replace("\"", "\"\"")}\""
  end
end
