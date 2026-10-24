defmodule TigooServerWeb.AdminSessionControllerTest do
  use TigooServerWeb.ConnCase, async: false

  setup do
    previous_config = Application.get_env(:tigoo_server, :admin_auth)
    Application.put_env(:tigoo_server, :admin_auth, username: "admin", password: "test-password")

    on_exit(fn ->
      if previous_config do
        Application.put_env(:tigoo_server, :admin_auth, previous_config)
      else
        Application.delete_env(:tigoo_server, :admin_auth)
      end
    end)

    :ok
  end

  test "redirects unauthenticated requests for every admin route", %{conn: conn} do
    conn = get(conn, ~p"/admin/users")

    assert redirected_to(conn) == "/admin/login"
  end

  test "creates an admin-only session for valid credentials", %{conn: conn} do
    conn = post(conn, ~p"/admin/login", %{admin: %{username: "admin", password: "test-password"}})

    assert redirected_to(conn) == "/admin"
    assert get_session(conn, :admin_authenticated) == true

    conn = get(conn, ~p"/admin/users")
    assert html_response(conn, :ok)
  end

  test "shows one generic error for invalid credentials", %{conn: conn} do
    conn =
      post(conn, ~p"/admin/login", %{admin: %{username: "admin", password: "wrong-password"}})

    assert redirected_to(conn) == "/admin/login"
    assert get_session(conn, :admin_authenticated) == nil
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid username or password."
  end

  test "logout clears only the admin authentication state", %{conn: conn} do
    conn =
      conn
      |> init_test_session(user_token: "normal-user-session", admin_authenticated: true)
      |> post(~p"/admin/logout")

    assert redirected_to(conn) == "/admin/login"
    assert get_session(conn, :admin_authenticated) == nil
    assert get_session(conn, :user_token) == "normal-user-session"
  end
end
