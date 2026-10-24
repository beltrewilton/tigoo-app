defmodule TigooServer.Accounts.OAuthHandoff do
  use Ecto.Schema

  import Ecto.Changeset

  alias TigooServer.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "oauth_handoffs" do
    belongs_to :user, User, type: :binary_id
    field :token_digest, :binary
    field :platform, :string
    field :attempt_id, :binary_id
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(handoff, attrs) do
    handoff
    |> cast(attrs, [:user_id, :token_digest, :platform, :attempt_id, :expires_at])
    |> validate_required([:user_id, :token_digest, :platform, :expires_at])
    |> validate_inclusion(:platform, ["desktop", "mobile"])
    |> unique_constraint(:token_digest)
    |> foreign_key_constraint(:user_id)
  end
end
