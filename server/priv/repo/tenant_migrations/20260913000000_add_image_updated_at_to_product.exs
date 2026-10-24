defmodule TigooServer.Repo.Migrations.AddImageUpdatedAtToProduct do
  use Ecto.Migration

  def up do
    product = tenant_table(:product)

    execute("""
    ALTER TABLE #{product}
    ADD COLUMN image_updated_at timestamp(0) without time zone
    """)

    execute("""
    UPDATE #{product}
    SET image_updated_at = COALESCE(date_create, CURRENT_TIMESTAMP)
    WHERE image_raw IS NOT NULL
      AND image_raw != ''
    """)
  end

  def down do
    execute("""
    ALTER TABLE #{tenant_table(:product)}
    DROP COLUMN image_updated_at
    """)
  end

  defp tenant_table(table) do
    "#{quoted_identifier(prefix() || "public")}.#{quoted_identifier(table)}"
  end

  defp quoted_identifier(identifier) do
    "\"#{identifier |> to_string() |> String.replace("\"", "\"\"")}\""
  end
end
