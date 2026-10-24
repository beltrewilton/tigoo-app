defmodule TigooServerWeb.AuthenticationControllerTest do
  use TigooServerWeb.ConnCase, async: false

  alias TigooServer.{Accounts, Authentication, Password, Repo, Tenants}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.Scope, as: EmployeeScope
  alias TigooServer.Retaily.{Store, User, UserStore, Users}

  @tenant "sales_seed_test"

  setup do
    unique = System.unique_integer([:positive])
    Tenants.put(@tenant)

    {:ok, admin} =
      Accounts.create_user(%{
        "name" => "Tenant Admin #{unique}",
        "email" => "admin-#{unique}@example.test",
        "tenant" => @tenant,
        "password" => "a-long-test-password"
      })

    store = Repo.insert!(%Store{name: "AUTH TEST STORE #{unique}"}, prefix: @tenant)

    {:ok, employee} =
      %User{}
      |> User.changeset(%{
        "username" => "employee#{unique}",
        "password" => "employee-test-password",
        "first_name" => "Employee",
        "last_name" => "Test"
      })
      |> Repo.insert(prefix: @tenant)

    Repo.insert!(%UserStore{user_id: employee.id, store_id: store.id}, prefix: @tenant)
    Repo.insert!(%EmployeeScope{user_id: employee.id, name: "sales.view"}, prefix: @tenant)
    Repo.insert!(%EmployeeScope{user_id: employee.id, name: "user.view"}, prefix: @tenant)

    %{admin: admin, employee: employee, store: store}
  end

  test "logs in a tenant admin through the unified endpoint", %{admin: admin} do
    response =
      build_conn()
      |> Map.put(:host, "#{@tenant}.localhost")
      |> post(~p"/api/login", %{identifier: admin.email, password: "a-long-test-password"})
      |> json_response(:ok)

    assert response["user"]["type"] == "admin"
    assert response["user"]["tenant"] == @tenant
    assert is_binary(response["token"])
  end

  test "verifies Retaily bcrypt hashes" do
    assert Password.verify(
             "secret",
             "$2b$12$EixZaYVK1fsbw1ZfbX3OXePaWxn96p36WQoeG6Lruj3vjPGga31lW"
           )
  end

  test "rejects reserved tenant identifiers" do
    changeset =
      Accounts.change_user(%TigooServer.Accounts.User{}, %{
        "name" => "Reserved Tenant",
        "email" => "reserved@example.test",
        "tenant" => "admin",
        "password" => "a-long-test-password"
      })

    refute changeset.valid?
    assert {"is reserved", _} = Keyword.fetch!(changeset.errors, :tenant)
  end

  test "logs in an employee and returns only assigned stores and scopes", %{
    employee: employee,
    store: store
  } do
    response =
      build_conn()
      |> Map.put(:host, "#{@tenant}.localhost")
      |> post(~p"/api/login", %{identifier: employee.username, password: "employee-test-password"})
      |> json_response(:ok)

    assert response["user"]["type"] == "employee"
    assert response["user"]["store_ids"] == [store.id]
    assert Enum.sort(response["user"]["scopes"]) == ["sales.view", "user.view"]
  end

  test "does not use a tenant supplied by the client", %{employee: employee} do
    response =
      build_conn()
      |> Map.put(:host, "#{@tenant}.localhost")
      |> post(~p"/api/login", %{
        identifier: employee.username,
        password: "employee-test-password",
        tenant: "wrong_tenant"
      })
      |> json_response(:ok)

    assert response["user"]["type"] == "employee"
  end

  test "invalidates an employee session when the employee is deactivated", %{employee: employee} do
    {:ok, token, _scope} =
      Authentication.login(%{
        "identifier" => employee.username,
        "password" => "employee-test-password"
      }, @tenant)

    employee |> Ecto.Changeset.change(is_active: 0) |> Repo.update!(prefix: @tenant)

    assert {:error, :unauthorized} = Authentication.authenticate(token)
  end

  test "allows a user.view employee to list users but not create them", %{employee: employee} do
    {:ok, token, scope} =
      Authentication.login(%{
        "identifier" => employee.username,
        "password" => "employee-test-password"
      }, @tenant)

    assert {:ok, authenticated_scope} = Authentication.authenticate(token)
    assert authenticated_scope.actor == :employee
    assert {:ok, users} = Users.list(scope)
    assert Enum.any?(users, &(&1.id == employee.id))

    assert {:error, :forbidden} =
             Users.create(scope, %{
               "username" => "notallowed#{System.unique_integer([:positive])}",
               "password" => "employee-test-password",
               "first_name" => "No",
               "last_name" => "Access",
               "store_ids" => [],
               "scopes" => []
             })
  end

  test "admin scope has tenant-wide user administration permission", %{admin: admin} do
    admin_scope = Scope.for_user(admin)

    assert Scope.allowed?(admin_scope, "user.view")
    assert Scope.allowed?(admin_scope, "user.setting")
    assert {:ok, _users} = Users.list(admin_scope)
  end
end
