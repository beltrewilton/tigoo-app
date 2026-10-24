defmodule TigooServer.Authentication do
  @moduledoc "Unified login and bearer-token authentication for tenant admins and employees."

  import Ecto.Query

  alias TigooServer.Accounts.{OAuthHandoff, OAuthLoginAttempt, Scope, User}
  alias TigooServer.{Accounts, Password, Repo, Tenants}
  alias TigooServer.Retaily.Scope, as: EmployeeScope
  alias TigooServer.Retaily.BusinessTime
  alias TigooServer.Retaily.User, as: Employee
  alias TigooServer.Retaily.UserStore

  @salt "api-session"

  def login(%{"identifier" => identifier, "password" => password})
      when is_binary(identifier) and is_binary(password) do
    login(%{"identifier" => identifier, "password" => password}, nil)
  end

  def login(_), do: {:error, :invalid_credentials}

  def login(%{"identifier" => identifier, "password" => password}, tenant)
      when is_binary(identifier) and is_binary(password) and is_binary(tenant) do
    IO.inspect(identifier, label: "login submitted identifier")

    result =
      case Accounts.get_user_by_email_and_tenant(identifier, tenant) do
        %User{tenant: ^tenant} = admin ->
          IO.inspect(admin_lookup_summary(admin), label: "login user lookup")
          authenticate_admin(admin, password)

        _ ->
          IO.inspect(%{actor: :employee, found?: false}, label: "login user lookup")
          authenticate_employee_in_tenant(tenant, identifier, password)
      end

    IO.inspect(login_result_summary(result), label: "login authentication result")
    result
  end

  def login(_params, _tenant), do: {:error, :invalid_credentials}

  @doc "Issues the application's normal API token for an already authenticated admin."
  def log_in_user(%User{} = user) do
    scope = Scope.for_user(user)
    {:ok, issue(scope), scope}
  end

  @doc "Creates a short-lived, single-use code for returning a browser OAuth result to Tauri."
  def create_tauri_handoff(%User{} = user, platform, attempt_id \\ nil)
      when platform in ["desktop", "mobile"] do
    code = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    attrs = %{
      user_id: user.id,
      token_digest: handoff_digest(code),
      platform: platform,
      attempt_id: attempt_id,
      expires_at: DateTime.add(DateTime.utc_now(), 120, :second)
    }

    case %OAuthHandoff{} |> OAuthHandoff.changeset(attrs) |> Repo.insert() do
      {:ok, _handoff} -> {:ok, code}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Atomically consumes a Tauri OAuth handoff code and returns its user."
  def consume_tauri_handoff(code) when is_binary(code) do
    now = DateTime.utc_now()

    Repo.transaction(fn ->
      handoff =
        Repo.one(
          from(h in OAuthHandoff,
            where: h.token_digest == ^handoff_digest(code) and h.expires_at > ^now,
            lock: "FOR UPDATE"
          )
        )

      case handoff do
        %OAuthHandoff{} ->
          Repo.delete!(handoff)

          case Repo.get(User, handoff.user_id) do
            %User{} = user -> user
            nil -> Repo.rollback(:unauthorized)
          end

        nil ->
          Repo.rollback(:unauthorized)
      end
    end)
    |> case do
      {:ok, %User{} = user} -> {:ok, user}
      _ -> {:error, :unauthorized}
    end
  end

  def consume_tauri_handoff(_), do: {:error, :unauthorized}

  def create_tauri_login_attempt(platform) when platform in ["desktop", "mobile"] do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    attempt_id = Ecto.UUID.generate()

    attrs = %{
      id: attempt_id,
      channel_token_digest: handoff_digest(token),
      platform: platform,
      status: "pending",
      expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
    }

    case %OAuthLoginAttempt{} |> OAuthLoginAttempt.changeset(attrs) |> Repo.insert() do
      {:ok, _} -> {:ok, %{attempt_id: attempt_id, channel_token: token, expires_in: 300}}
      {:error, reason} -> {:error, reason}
    end
  end

  def authenticate_tauri_login_attempt(attempt_id, token)
      when is_binary(attempt_id) and is_binary(token) do
    case Repo.get(OAuthLoginAttempt, attempt_id) do
      %OAuthLoginAttempt{status: status, expires_at: expires_at, channel_token_digest: digest} =
          attempt
      when status in ["pending", "success", "error"] ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt and
             Plug.Crypto.secure_compare(digest, handoff_digest(token)),
           do: {:ok, attempt},
           else: {:error, :unauthorized}

      _ ->
        {:error, :unauthorized}
    end
  end

  def authenticate_tauri_login_attempt(_, _), do: {:error, :unauthorized}

  def valid_tauri_login_attempt?(attempt_id) when is_binary(attempt_id) do
    case Repo.get(OAuthLoginAttempt, attempt_id) do
      %OAuthLoginAttempt{status: "pending", expires_at: expires_at} ->
        DateTime.compare(expires_at, DateTime.utc_now()) == :gt

      _ ->
        false
    end
  end

  def valid_tauri_login_attempt?(_), do: false

  def complete_tauri_login_attempt(attempt_id, %User{} = user) do
    now = DateTime.utc_now()

    case Repo.update_all(
           from(a in OAuthLoginAttempt,
             where: a.id == ^attempt_id and a.status == "pending" and a.expires_at > ^now
           ),
           set: [status: "success", user_id: user.id]
         ) do
      {1, _} -> login_attempt_result(attempt_id)
      _ -> {:error, :login_attempt_expired}
    end
  end

  def fail_tauri_login_attempt(attempt_id, error_code) do
    now = DateTime.utc_now()

    Repo.update_all(
      from(a in OAuthLoginAttempt,
        where: a.id == ^attempt_id and a.status == "pending" and a.expires_at > ^now
      ),
      set: [status: "error", error_code: error_code]
    )

    login_attempt_result(attempt_id)
  end

  def login_attempt_result(attempt_id) do
    case Repo.get(OAuthLoginAttempt, attempt_id) do
      %OAuthLoginAttempt{
        status: "success",
        user_id: user_id,
        platform: platform,
        expires_at: expires_at
      }
      when not is_nil(user_id) ->
        with :gt <- DateTime.compare(expires_at, DateTime.utc_now()),
             %User{} = user <- Repo.get(User, user_id),
             {:ok, code} <- create_tauri_handoff(user, platform, attempt_id) do
          {:ok, %{status: "success", attempt_id: attempt_id, exchange_code: code}}
        else
          _ -> {:error, :login_attempt_expired}
        end

      %OAuthLoginAttempt{status: "error", error_code: code} ->
        {:ok, %{status: "error", attempt_id: attempt_id, error: code || "google_sign_in_failed"}}

      %OAuthLoginAttempt{status: "pending"} ->
        {:ok, %{status: "pending", attempt_id: attempt_id}}

      _ ->
        {:error, :login_attempt_expired}
    end
  end

  def authenticate(token) when is_binary(token) do
    with {:ok, payload} <-
           Phoenix.Token.verify(TigooServerWeb.Endpoint, @salt, token, max_age: 86_400),
         {:ok, scope} <- scope_from_payload(payload) do
      {:ok, scope}
    else
      _ -> {:error, :unauthorized}
    end
  end

  def authenticate(_), do: {:error, :unauthorized}

  defp authenticate_admin(admin, password) do
    verified? = Password.verify(password, admin.hashed_password)
    IO.inspect(verified?, label: "login password verification")

    if verified? do
      scope = Scope.for_user(admin)
      {:ok, issue(scope), scope}
    else
      {:error, :invalid_credentials}
    end
  end

  defp authenticate_employee_in_tenant(tenant, username, password) do
    employee = Repo.one(from(user in Employee, where: user.username == ^username), prefix: tenant)

    IO.inspect(employee_lookup_summary(employee, tenant), label: "login user lookup")

    verified? =
      case employee do
        %Employee{is_active: 1, password: stored_password} when is_binary(stored_password) ->
          Password.verify(password, stored_password)

        _ ->
          false
      end

    IO.inspect(verified?, label: "login password verification")

    case {employee, verified?} do
      {%Employee{is_active: 1} = employee, true} ->
        employee =
          Repo.update!(Ecto.Changeset.change(employee, last_login: now()), prefix: tenant)

        scope = employee_scope(employee, tenant)
        {:ok, issue(scope), scope}

      _ ->
        {:error, :invalid_credentials}
    end
  end

  # Temporary login diagnostics intentionally exclude password material, hashes, and tokens.
  defp admin_lookup_summary(admin),
    do: %{actor: :admin, found?: true, id: admin.id, tenant: admin.tenant}

  defp employee_lookup_summary(nil, tenant),
    do: %{actor: :employee, found?: false, tenant: tenant}

  defp employee_lookup_summary(employee, tenant),
    do: %{
      actor: :employee,
      found?: true,
      id: employee.id,
      active?: employee.is_active == 1,
      tenant: tenant
    }

  defp login_result_summary({:ok, _token, scope}),
    do: %{
      authenticated?: true,
      actor: scope.actor,
      actor_id: scope.actor_id,
      tenant: scope.tenant
    }

  defp login_result_summary({:error, reason}), do: %{authenticated?: false, reason: reason}

  defp scope_from_payload(%{"actor" => "admin", "id" => id, "tenant" => tenant}) do
    case Repo.get(User, id) do
      %User{tenant: ^tenant} = admin -> {:ok, Scope.for_user(admin)}
      _ -> {:error, :unauthorized}
    end
  end

  defp scope_from_payload(%{"actor" => "employee", "id" => id, "tenant" => tenant})
       when is_integer(id) do
    if Tenants.exists?(tenant) do
      case Repo.get(Employee, id, prefix: tenant) do
        %Employee{is_active: 1} = employee -> {:ok, employee_scope(employee, tenant)}
        _ -> {:error, :unauthorized}
      end
    else
      {:error, :unauthorized}
    end
  end

  defp scope_from_payload(_), do: {:error, :unauthorized}

  defp employee_scope(employee, tenant) do
    scopes =
      Repo.all(
        from(scope in EmployeeScope, where: scope.user_id == ^employee.id, select: scope.name),
        prefix: tenant
      )
      |> Enum.uniq()

    store_ids =
      Repo.all(
        from(link in UserStore, where: link.user_id == ^employee.id, select: link.store_id),
        prefix: tenant
      )

    %TigooServer.Accounts.Scope{
      user: %{name: employee.username, tenant: tenant},
      tenant: tenant,
      actor: :employee,
      actor_id: employee.id,
      login: employee.username,
      pic: employee.pic,
      scopes: scopes,
      store_ids: store_ids
    }
  end

  defp issue(scope),
    do:
      Phoenix.Token.sign(TigooServerWeb.Endpoint, @salt, %{
        "actor" => Atom.to_string(scope.actor),
        "id" => scope.actor_id,
        "tenant" => scope.tenant
      })

  defp handoff_digest(code), do: :crypto.hash(:sha256, code)

  defp now, do: BusinessTime.local_now()
end
