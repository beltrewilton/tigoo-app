defmodule TigooServer.Accounts do
  import Ecto.Query, only: [from: 2]

  alias TigooServer.Accounts.{Company, User, UserCompany, UserToken}
  alias TigooServer.{Repo, Tenants}
  alias TigooServer.Retaily.Store

  def list_users do
    from(user in User, order_by: [asc: user.name, asc: user.email])
    |> Repo.all()
  end

  def get_user_by_email(email) when is_binary(email), do: Repo.get_by(User, email: email)

  def get_user_by_email_and_tenant(email, tenant) when is_binary(email) and is_binary(tenant),
    do: Repo.get_by(User, email: email, tenant: tenant)

  def get_user(id), do: Repo.get(User, id)

  def get_company_for_user(%User{tenant: tenant, id: user_id})
      when is_binary(tenant) and tenant != "" do
    Repo.one(
      from(company in Company,
        join: membership in UserCompany,
        on: membership.company_id == company.id,
        where: membership.user_id == ^user_id,
        limit: 1
      ),
      prefix: Triplex.to_prefix(tenant)
    )
  end

  def get_company_for_user(_user), do: nil

  def change_user(%User{} = user, attrs \\ %{}), do: User.changeset(user, attrs)

  def create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Finds or creates an unconfirmed account from verified Google user info."
  def upsert_user_from_google(user_info)
      when is_map(user_info) do
    upsert_google_user(user_info)
  end

  @doc false
  # The desktop/mobile OAuth handoff uses the same identity-only Google account
  # flow as browser sign-in; only the callback delivery differs.
  def upsert_tauri_user_from_google(user_info)
      when is_map(user_info) do
    upsert_google_user(user_info)
  end

  defp upsert_google_user(user_info) do
    google_uid = user_info["sub"] || user_info["id"]
    email = user_info["email"]
    name = user_info["name"] || email
    email_verified? = user_info["email_verified"] == true

    with true <- email_verified?,
         true <- is_binary(google_uid) and byte_size(google_uid) > 0,
         true <- is_binary(email) and byte_size(email) > 0 do
      attrs = %{
        email: email,
        name: name,
        google_uid: google_uid,
        google_picture_url: user_info["picture"]
      }

      case Repo.get_by(User, google_uid: google_uid) || Repo.get_by(User, email: email) do
        %User{} = user ->
          user
          |> User.google_oauth_changeset(attrs)
          |> Repo.update()

        nil ->
          create_google_user(attrs)
      end
    else
      _ -> {:error, :invalid_google_user}
    end
  end

  defp create_google_user(attrs) do
    %User{}
    |> User.google_oauth_changeset(attrs)
    |> Repo.insert()
  end

  def confirm_user(%User{confirmed_at: nil} = user) do
    user
    |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  def confirm_user(%User{} = user), do: {:ok, user}

  def change_company(%Company{} = company, attrs \\ %{}), do: Company.changeset(company, attrs)

  def change_tenant(%User{} = user, attrs \\ %{}), do: User.tenant_changeset(user, attrs)

  @doc "Creates a company tenant for a confirmed browser account without creating another user."
  def create_tenant_for_user(%User{confirmed_at: nil}, _tenant_attrs, _company_attrs),
    do: {:error, :unconfirmed}

  def create_tenant_for_user(%User{tenant: tenant}, _tenant_attrs, _company_attrs)
      when is_binary(tenant) and tenant != "",
      do: {:error, :tenant_exists}

  def create_tenant_for_user(%User{} = user, tenant_attrs, company_attrs)
      when is_map(tenant_attrs) and is_map(company_attrs) do
    tenant_changeset = change_tenant(user, tenant_attrs)
    company_changeset = change_company(%Company{}, company_attrs)

    cond do
      not tenant_changeset.valid? ->
        {:error, :tenant, tenant_changeset}

      not company_changeset.valid? ->
        {:error, :company, company_changeset}

      true ->
        case Repo.update(tenant_changeset) do
          {:ok, updated_user} ->
            case create_tenant_company(updated_user.tenant, updated_user.id, company_changeset) do
              :ok ->
                Tenants.put(updated_user.tenant)
                {:ok, updated_user}

              {:error, :tenant, reason} ->
                IO.inspect(
                  %{
                    tenant: updated_user.tenant,
                    user_id: updated_user.id,
                    reason: reason
                  },
                  label: "tenant provisioning failed"
                )

                Repo.update(Ecto.Changeset.change(updated_user, tenant: nil))
                {:error, :provisioning, reason}
            end

          {:error, changeset} ->
            {:error, :tenant, changeset}
        end
    end
  end

  def create_company_user(user_attrs, company_attrs) do
    user_changeset = User.changeset(%User{}, user_attrs)
    company_changeset = Company.changeset(%Company{}, company_attrs)

    cond do
      not user_changeset.valid? ->
        {:error, :user, user_changeset}

      not company_changeset.valid? ->
        {:error, :company, company_changeset}

      true ->
        create_valid_company_user(user_changeset, company_changeset)
    end
  end

  def change_user_token(%UserToken{} = user_token, attrs \\ %{}),
    do: UserToken.changeset(user_token, attrs)

  def create_user_token(attrs) do
    attrs =
      attrs
      |> Map.put("context", "session")
      |> Map.put("token", :crypto.strong_rand_bytes(32))

    %UserToken{}
    |> UserToken.changeset(attrs)
    |> Ecto.Changeset.put_change(:token, attrs["token"])
    |> Repo.insert()
  end

  @doc "Encodes a binary session token for the desktop API Authorization header."
  def encode_session_token(%UserToken{token: token}) when is_binary(token) do
    Base.url_encode64(token, padding: false)
  end

  @doc "Returns the user for a valid binary session token, or nil."
  def get_user_by_session_token(token) when is_binary(token) do
    from(user in User,
      join: user_token in UserToken,
      on: user_token.user_id == user.id,
      where: user_token.token == ^token and user_token.context == "session",
      select: user
    )
    |> Repo.one()
  end

  defp create_valid_company_user(user_changeset, company_changeset) do
    case Repo.insert(user_changeset) do
      {:ok, user} ->
        case create_tenant_company(user.tenant, user.id, company_changeset) do
          :ok ->
            Tenants.put(user.tenant)
            {:ok, user}

          {:error, :tenant, reason} ->
            IO.inspect(
              %{
                tenant: user.tenant,
                user_id: user.id,
                reason: reason
              },
              label: "tenant provisioning failed"
            )

            Repo.delete(user)
            {:error, :tenant, reason}
        end

      {:error, changeset} ->
        {:error, :user, changeset}
    end
  end

  defp create_tenant_company(tenant, user_id, company_changeset) do
    case Triplex.create_schema(tenant, Repo, fn created_tenant, repo ->
           with {:ok, _migrations} <- Triplex.migrate(created_tenant, repo) do
             repo.transaction(fn ->
               with {:ok, company} <-
                      repo.insert(company_changeset, prefix: Triplex.to_prefix(created_tenant)),
                    {:ok, _user_company} <-
                      create_user_company(repo, created_tenant, user_id, company.id) do
                 case create_default_store(repo, created_tenant, company.id) do
                   {:ok, _store} -> created_tenant
                   {:error, reason} ->
                     IO.inspect(
                       %{
                         tenant: created_tenant,
                         prefix: Triplex.to_prefix(created_tenant),
                         user_id: user_id,
                         company_id: company.id,
                         step: :default_store,
                         reason: reason
                       },
                       label: "tenant provisioning rollback"
                     )

                     repo.rollback(reason)
                 end
               else
                 {:error, reason} ->
                   IO.inspect(
                     %{
                       tenant: created_tenant,
                       prefix: Triplex.to_prefix(created_tenant),
                       user_id: user_id,
                       step: :company_or_membership,
                       reason: reason
                     },
                     label: "tenant provisioning rollback"
                   )

                   repo.rollback(reason)
               end
             end)
           end
         end) do
      {:ok, _tenant} -> :ok
      {:error, reason} ->
        IO.inspect(
          %{
            tenant: tenant,
            prefix: Triplex.to_prefix(tenant),
            user_id: user_id,
            reason: reason
          },
          label: "triplex create schema failed"
        )

        {:error, :tenant, reason}
    end
  end

  defp create_user_company(repo, tenant, user_id, company_id) do
    %UserCompany{}
    |> UserCompany.changeset(%{user_id: user_id, company_id: company_id})
    |> repo.insert(prefix: Triplex.to_prefix(tenant))
  end

  defp create_default_store(repo, tenant, company_id) do
    %Store{}
    |> Store.changeset(%{name: "Main Store", company_id: to_string(company_id)})
    |> repo.insert(prefix: Triplex.to_prefix(tenant))
  end
end
