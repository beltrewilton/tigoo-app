defmodule TigooServer.Accounts.User do
  use Ecto.Schema

  import Ecto.Changeset

  alias TigooServer.Password
  alias TigooServer.Tenants

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "users" do
    field :email, :string
    field :name, :string
    field :tenant, :string
    field :google_uid, :string
    field :google_picture_url, :string
    field :hashed_password, :string
    field :password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :tenant, :password])
    |> validate_required([:email, :name, :tenant, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_format(:tenant, ~r/^[a-z][a-z0-9_-]{2,62}$/,
      message: "must be a lowercase tenant identifier (letters, numbers, hyphens, and underscores)"
    )
    |> validate_allowed_tenant()
    |> validate_length(:password, min: 6, max: 72)
    |> unique_constraint(:email)
    |> hash_password()
  end

  def tenant_changeset(user, attrs) do
    user
    |> cast(attrs, [:tenant])
    |> validate_required([:tenant])
    |> validate_format(:tenant, ~r/^[a-z][a-z0-9_-]{2,62}$/,
      message: "must be a lowercase tenant identifier (letters, numbers, hyphens, and underscores)"
    )
    |> validate_allowed_tenant()
  end

  @doc "Creates or updates a user authenticated by Google OAuth."
  def google_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :name,
      :google_uid,
      :google_picture_url
    ])
    |> validate_required([:email, :name, :google_uid])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:email)
    |> unique_constraint(:google_uid)
  end

  defp hash_password(changeset) do
    if changeset.valid? do
      case get_change(changeset, :password) do
        nil ->
          changeset

        password ->
          changeset
          |> put_change(:hashed_password, Password.hash(password))
          |> delete_change(:password)
      end
    else
      changeset
    end
  end

  defp validate_allowed_tenant(changeset) do
    validate_change(changeset, :tenant, fn :tenant, tenant ->
      cond do
        Tenants.reserved?(tenant) ->
          [tenant: "is reserved"]

        Tenants.valid_identifier?(tenant) ->
          []

        true ->
          [tenant: "must be a lowercase tenant identifier (letters, numbers, hyphens, and underscores)"]
      end
    end)
  end
end
