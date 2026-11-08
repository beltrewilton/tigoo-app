defmodule TigooServer.Repo.Migrations.SetE31CurrentSequence do
  use Ecto.Migration

  def up do
    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""

    execute """
    UPDATE #{schema}.app_sequence
    SET current_seq = 2
    WHERE code = 'E31'
    """
  end

  def down do
    # Previous counter values cannot be reconstructed.
    :ok
  end
end
