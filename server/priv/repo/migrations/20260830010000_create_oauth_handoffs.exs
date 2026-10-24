defmodule TigooServer.Repo.Migrations.CreateOauthHandoffs do
  use Ecto.Migration

  def change do
    create table(:oauth_handoffs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token_digest, :binary, null: false
      add :platform, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:oauth_handoffs, [:token_digest])
    create index(:oauth_handoffs, [:expires_at])
  end
end
