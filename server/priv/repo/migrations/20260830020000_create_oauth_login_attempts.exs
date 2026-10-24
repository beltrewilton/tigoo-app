defmodule TigooServer.Repo.Migrations.CreateOauthLoginAttempts do
  use Ecto.Migration

  def change do
    create table(:oauth_login_attempts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :channel_token_digest, :binary, null: false
      add :platform, :string, null: false
      add :status, :string, null: false
      add :error_code, :string
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:oauth_login_attempts, [:channel_token_digest])
    create index(:oauth_login_attempts, [:expires_at])

    alter table(:oauth_handoffs) do
      add :attempt_id, :binary_id
    end
  end
end
