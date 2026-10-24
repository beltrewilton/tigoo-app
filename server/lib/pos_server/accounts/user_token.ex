defmodule TigooServer.Accounts.UserToken do
  use Ecto.Schema

  import Ecto.Changeset

  alias TigooServer.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "users_tokens" do
    belongs_to :user, User, type: :binary_id
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(user_token, attrs) do
    user_token
    |> cast(attrs, [:user_id, :context, :sent_to])
    |> validate_required([:user_id, :context])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:token, name: :users_tokens_context_token_index)
  end
end
