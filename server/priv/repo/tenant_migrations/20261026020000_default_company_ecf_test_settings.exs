defmodule TigooServer.Repo.Migrations.DefaultCompanyEcfTestSettings do
  use Ecto.Migration

  # Match the existing simulation default, not a production DGII authorization.
  def up do
    alter table(:company) do
      modify :address, :string, default: "AVE ITALIA 54"
      modify :ecf_test_sequence_expiry, :date, default: fragment("'2028-12-31'::date")
    end

    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""
    execute """
    UPDATE #{schema}.company
    SET address = 'AVE ITALIA 54'
    WHERE address IS NULL OR btrim(address) = ''
    """
    execute """
    UPDATE #{schema}.company
    SET ecf_test_sequence_expiry = DATE '2028-12-31'
    WHERE ecf_test_sequence_expiry IS NULL
    """
  end

  def down do
    alter table(:company) do
      modify :address, :string, default: nil
      modify :ecf_test_sequence_expiry, :date, default: nil
    end
  end
end
