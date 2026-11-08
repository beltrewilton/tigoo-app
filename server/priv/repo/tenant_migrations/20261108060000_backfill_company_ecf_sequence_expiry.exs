defmodule TigooServer.Repo.Migrations.BackfillCompanyEcfSequenceExpiry do
  use Ecto.Migration

  def up do
    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""

    execute """
    UPDATE #{schema}.company
    SET ecf_sequence_expiry = ecf_test_sequence_expiry
    WHERE ecf_sequence_expiry IS NULL
      AND ecf_test_sequence_expiry IS NOT NULL
    """
  end

  def down do
    # Copied dates cannot be distinguished from independently configured dates.
    :ok
  end
end
