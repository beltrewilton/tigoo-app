defmodule TigooServer.Accounts.OAuthLoginAttempt do
  use Ecto.Schema
  import Ecto.Changeset

  alias TigooServer.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "oauth_login_attempts" do
    belongs_to :user, User, type: :binary_id
    field :channel_token_digest, :binary
    field :platform, :string
    field :status, :string
    field :error_code, :string
    field :expires_at, :utc_datetime
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(attempt, attrs) do
    attempt
    |> cast(attrs, [
      :id,
      :user_id,
      :channel_token_digest,
      :platform,
      :status,
      :error_code,
      :expires_at
    ])
    |> validate_required([:id, :channel_token_digest, :platform, :status, :expires_at])
    |> validate_inclusion(:platform, ["desktop", "mobile"])
    |> validate_inclusion(:status, ["pending", "success", "error"])
    |> unique_constraint(:channel_token_digest)
  end
end
