defmodule TigooServer.Repo.Migrations.SetCompanyEcfSequenceExpiry do
  use Ecto.Migration

  def up do
    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""

    execute """
    UPDATE #{schema}.company
    SET ecf_sequence_expiry = DATE '2027-12-31'
    """
  end

  def down do
    # Previous company expiry values cannot be reconstructed.
    :ok
  end
end
