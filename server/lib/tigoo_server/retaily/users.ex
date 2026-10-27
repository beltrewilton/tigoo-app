defmodule TigooServer.Retaily.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias TigooServer.Retaily.BusinessTime
  alias TigooServer.Password

  schema "app_users" do
    field :username, :string
    field :password, :string
    field :first_name, :string
    field :last_name, :string
    field :is_active, :integer, default: 1
    field :ecf_test_enabled, :boolean, default: false
    field :date_joined, :naive_datetime
    field :last_login, :naive_datetime
    field :pic, :string

    has_many :user_stores, TigooServer.Retaily.UserStore
    has_many :scopes, TigooServer.Retaily.Scope
    many_to_many :stores, TigooServer.Retaily.Store, join_through: TigooServer.Retaily.UserStore
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :first_name, :last_name, :is_active, :pic, :date_joined])
    |> validate_required([:username, :first_name, :last_name])
    |> validate_length(:username, max: 20)
    |> validate_length(:password, max: 72)
    |> unique_constraint(:username)
    |> require_password_for_new_user(user)
    |> default_joined_at(user)
    |> hash_password()
  end

  defp require_password_for_new_user(changeset, %__MODULE__{id: nil}),
    do: validate_required(changeset, [:password])

  defp require_password_for_new_user(changeset, _user), do: changeset

  defp default_joined_at(changeset, %__MODULE__{id: nil}) do
    if get_field(changeset, :date_joined) do
      changeset
    else
      put_change(
        changeset,
        :date_joined,
        BusinessTime.local_now()
      )
    end
  end

  defp default_joined_at(changeset, _user), do: changeset

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password, Password.hash(password))
    end
  end
end

defmodule TigooServer.Retaily.UserStore do
  use Ecto.Schema

  @primary_key false

  schema "app_user_store" do
    belongs_to :user, TigooServer.Retaily.User, primary_key: true
    belongs_to :store, TigooServer.Retaily.Store, primary_key: true
  end
end

defmodule TigooServer.Retaily.Scope do
  use Ecto.Schema

  schema "scopes" do
    field :name, :string

    belongs_to :user, TigooServer.Retaily.User
  end
end

defmodule TigooServer.Retaily.ScopeList do
  use Ecto.Schema

  schema "scope_list" do
    field :name, :string
  end
end
