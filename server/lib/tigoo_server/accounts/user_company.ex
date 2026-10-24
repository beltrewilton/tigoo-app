defmodule TigooServer.Accounts.UserCompany do
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false

  schema "users_companies" do
    field :user_id, :binary_id
    field :company_id, :binary_id
  end

  def changeset(user_company, attrs) do
    user_company
    |> cast(attrs, [:user_id, :company_id])
    |> validate_required([:user_id, :company_id])
    |> unique_constraint([:user_id, :company_id])
  end
end
