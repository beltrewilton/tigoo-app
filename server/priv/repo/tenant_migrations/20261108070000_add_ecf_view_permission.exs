defmodule TigooServer.Repo.Migrations.AddEcfViewPermission do
  use Ecto.Migration

  def up do
    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""

    execute """
    INSERT INTO #{schema}.scope_list (name)
    SELECT 'ecf.view'
    WHERE NOT EXISTS (SELECT 1 FROM #{schema}.scope_list WHERE name = 'ecf.view')
    """
  end

  def down do
    schema = "\"" <> String.replace(prefix(), "\"", "\"\"") <> "\""
    execute "DELETE FROM #{schema}.scopes WHERE name = 'ecf.view'"
    execute "DELETE FROM #{schema}.scope_list WHERE name = 'ecf.view'"
  end
end
