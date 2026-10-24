defmodule TigooServer.Repo.Migrations.AddGoogleOauthFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :google_uid, :string
      add :google_picture_url, :string
    end

    create unique_index(:users, [:google_uid])
  end
end
