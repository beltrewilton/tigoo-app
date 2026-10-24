defmodule TigooServerWeb.LandingControllerTest do
  use TigooServerWeb.ConnCase

  alias TigooServer.Tenants

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "tigoo"
  end

  test "GET /privacy-policy is public", %{conn: conn} do
    conn = get(conn, ~p"/privacy-policy")
    assert html_response(conn, 200) =~ "Política de privacidad"
  end

  test "GET /terms-of-service is public", %{conn: conn} do
    conn = get(conn, ~p"/terms-of-service")
    assert html_response(conn, 200) =~ "Términos de servicio"
  end

  test "base-domain tenant app routes show the tenant-required page", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "localhost")
      |> get(~p"/pos/login")

    assert html_response(conn, 404) =~
             "This page requires your organization's unique web address"
  end

  test "unknown tenant subdomains render the standard 404", %{conn: conn} do
    conn =
      conn
      |> Map.put(:host, "isnotregistered.localhost")
      |> get(~p"/pos/login")

    assert html_response(conn, 404) == "Not Found"
  end

  test "unknown routes render the standard 404", %{conn: conn} do
    conn = get(conn, "/any")
    assert html_response(conn, 404) == "Not Found"
  end

  test "registered tenant subdomains can reach tenant login", %{conn: conn} do
    Tenants.put("sales-seed-test")

    conn =
      conn
      |> Map.put(:host, "sales-seed-test.localhost")
      |> get(~p"/pos/login")

    assert html_response(conn, 200) =~ "@sales-seed-test"
  end
end
