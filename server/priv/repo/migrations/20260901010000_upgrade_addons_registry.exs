defmodule TigooServer.Repo.Migrations.UpgradeAddonsRegistry do
  use Ecto.Migration

  def up do
    # `CreateAddons` already uses the new column names for fresh installs, while
    # databases created before the registry upgrade still use `slug` and
    # `module`. Keep this migration compatible with both states.
    execute """
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = 'addons' AND column_name = 'slug'
      ) THEN
        ALTER TABLE addons RENAME COLUMN slug TO identifier;
      END IF;

      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = current_schema() AND table_name = 'addons' AND column_name = 'module'
      ) THEN
        ALTER TABLE addons RENAME COLUMN module TO handler;
      END IF;
    END $$;
    """

    execute "ALTER TABLE addons ADD COLUMN IF NOT EXISTS route varchar NOT NULL DEFAULT ''"
    execute "ALTER TABLE addons ADD COLUMN IF NOT EXISTS installed boolean NOT NULL DEFAULT true"
    execute "ALTER TABLE addons ADD COLUMN IF NOT EXISTS installed_at timestamp(0)"

    execute "UPDATE addons SET route = '/addons/' || identifier, installed_at = COALESCE(inserted_at, NOW())"
    execute "ALTER TABLE addons ALTER COLUMN route DROP DEFAULT"
    execute "ALTER TABLE addons ALTER COLUMN installed_at SET NOT NULL"

    execute """
    DO $$
    BEGIN
      IF to_regclass('addons_slug_index') IS NOT NULL
         AND to_regclass('addons_identifier_index') IS NULL THEN
        ALTER INDEX addons_slug_index RENAME TO addons_identifier_index;
      END IF;
    END $$;
    """

    execute "CREATE UNIQUE INDEX IF NOT EXISTS addons_route_index ON addons (route)"
  end

  def down do
    drop_if_exists unique_index(:addons, [:route])
    execute "ALTER INDEX addons_identifier_index RENAME TO addons_slug_index"

    alter table(:addons) do
      remove :installed_at
      remove :installed
      remove :route
    end

    rename table(:addons), :handler, to: :module
    rename table(:addons), :identifier, to: :slug
  end
end
