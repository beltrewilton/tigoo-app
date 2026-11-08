defmodule TigooServer.Repo.Migrations.RemoveTestSequenceCodePrefix do
  use Ecto.Migration

  def up do
    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""

    execute """
    UPDATE #{schema}.app_sequence
    SET code = substring(code FROM 6)
    WHERE code ~ '^TEST_E[0-9]{2}$'
    """

  end

  def down do
    raise "Restoring TEST_ codes requires identifying which E codes existed before this migration"
  end
end
