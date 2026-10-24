defmodule TigooServer.Retaily.Users do
  @moduledoc false

  import Ecto.Query

  alias TigooServer.Repo
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.Scope, as: EmployeeScope
  alias TigooServer.Retaily.{ScopeList, Store, User, UserStore}

  def list(scope), do: with(:ok <- authorize(scope, "user.view"), do: {:ok, users(scope.tenant)})

  def get(scope, id) do
    with :ok <- authorize(scope, "user.view"),
         %User{} = user <- Repo.get(User, id, prefix: scope.tenant) do
      {:ok, serialize(user, scope.tenant)}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  def create(scope, attrs), do: save(scope, %User{}, attrs, :create)

  def options(scope) do
    with :ok <- authorize(scope, "user.view") do
      stores =
        Repo.all(
          from(store in Store,
            order_by: [asc: store.name],
            select: %{id: store.id, name: store.name}
          ),
          prefix: scope.tenant
        )

      scopes =
        Repo.all(
          from(scope_item in ScopeList, order_by: [asc: scope_item.name], select: scope_item.name),
          prefix: scope.tenant
        )

      {:ok, %{stores: stores, scopes: scopes}}
    end
  end

  def update(scope, id, attrs), do: update_user(scope, id, attrs)

  def deactivate(scope, id), do: update_user(scope, id, %{"is_active" => 0})

  defp update_user(scope, id, attrs) do
    with :ok <- authorize(scope, "user.view"),
         %User{} = user <- Repo.get(User, id, prefix: scope.tenant) do
      persist(user, attrs, scope.tenant, :update)
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp save(scope, user, attrs, :create) do
    with :ok <- authorize(scope, "user.view"), do: persist(user, attrs, scope.tenant, :create)
  end

  defp persist(user, attrs, tenant, _action) do
    store_ids = Map.get(attrs, "store_ids", Map.get(attrs, :store_ids, []))
    scope_names = Map.get(attrs, "scopes", Map.get(attrs, :scopes, []))
    attrs = attrs |> Map.drop(["store_ids", "scopes"]) |> Map.drop([:store_ids, :scopes])

    Repo.transaction(fn ->
      with :ok <- valid_store_ids?(store_ids, tenant),
           :ok <- valid_scopes?(scope_names, tenant),
           {:ok, user} <- user |> User.changeset(attrs) |> Repo.insert_or_update(prefix: tenant),
           {_, _} <-
             Repo.delete_all(from(link in UserStore, where: link.user_id == ^user.id),
               prefix: tenant
             ),
           {_, _} <-
             Repo.delete_all(
               from(employee_scope in EmployeeScope, where: employee_scope.user_id == ^user.id),
               prefix: tenant
             ),
           :ok <- insert_stores(user.id, store_ids, tenant),
           :ok <- insert_scopes(user.id, scope_names, tenant) do
        serialize(user, tenant)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, user} -> {:ok, user}
      {:error, reason} -> {:error, reason}
    end
  end

  defp users(tenant),
    do:
      Repo.all(from(user in User, order_by: [desc: user.is_active, asc: user.username]), prefix: tenant)
      |> Enum.map(&serialize(&1, tenant))

  defp serialize(user, tenant),
    do: %{
      id: user.id,
      username: user.username,
      first_name: user.first_name,
      last_name: user.last_name,
      is_active: user.is_active,
      pic: user.pic,
      date_joined: user.date_joined,
      last_login: user.last_login,
      store_ids:
        Repo.all(from(link in UserStore, where: link.user_id == ^user.id, select: link.store_id),
          prefix: tenant
        ),
      scopes:
        Repo.all(
          from(scope in EmployeeScope, where: scope.user_id == ^user.id, select: scope.name),
          prefix: tenant
        )
        |> Enum.uniq()
    }

  defp valid_store_ids?(ids, tenant) when is_list(ids) do
    if Enum.all?(ids, &is_integer/1) and
         Repo.aggregate(from(store in Store, where: store.id in ^ids), :count, prefix: tenant) ==
           length(Enum.uniq(ids)),
       do: :ok,
       else: {:error, :invalid_store_ids}
  end

  defp valid_store_ids?(_, _), do: {:error, :invalid_store_ids}

  defp valid_scopes?(scopes, tenant) when is_list(scopes) do
    if Enum.all?(scopes, &is_binary/1) do
      names = Enum.uniq(scopes)

      if Repo.aggregate(from(scope in ScopeList, where: scope.name in ^names), :count,
           prefix: tenant
         ) == length(names),
         do: :ok,
         else: {:error, :invalid_scopes}
    else
      {:error, :invalid_scopes}
    end
  end

  defp valid_scopes?(_, _), do: {:error, :invalid_scopes}

  defp insert_stores(id, ids, tenant),
    do:
      Enum.reduce_while(Enum.uniq(ids), :ok, fn store_id, :ok ->
        case Repo.insert(%UserStore{user_id: id, store_id: store_id}, prefix: tenant) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

  defp insert_scopes(id, names, tenant),
    do:
      Enum.reduce_while(Enum.uniq(names), :ok, fn name, :ok ->
        case Repo.insert(%EmployeeScope{name: name, user_id: id}, prefix: tenant) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

  defp authorize(scope, permission) do
    if is_binary(scope.tenant) and Scope.allowed?(scope, permission),
      do: :ok,
      else: {:error, :forbidden}
  end
end
