defmodule TigooServerWeb.CustomerControllerTest do
  use TigooServerWeb.ConnCase, async: false

  alias TigooServer.Accounts
  alias TigooServer.Repo
  alias TigooServer.Retaily.Client

  @tenant "sales_seed_test"
  @prefix "sales_seed_test"

  setup do
    Process.delete(:current_tenant)

    Enum.each(
      [{30_218, "EXISTING CUSTOMER"}, {30_219, "OLDER CUSTOMER"}, {30_220, "MARIA CUSTOMER"}],
      fn {id, name} ->
        Repo.insert!(
          %Client{id: id, name: name, celphone: if(id == 30_220, do: "809-555-0199", else: nil)},
          prefix: @prefix
        )
      end
    )

    {:ok, token} = token_for("walex")
    %{walex_conn: authenticated_conn(token)}
  end

  test "lists the most recently registered customers and filters by name or phone", %{
    walex_conn: conn
  } do
    customers = conn |> get(~p"/api/customers") |> json_response(:ok)
    assert Enum.take(Enum.map(customers["entries"], & &1["id"]), 2) == [30_220, 30_219]

    assert authenticated_conn_for("walex")
           |> get(~p"/api/customers?search=MARIA")
           |> json_response(:ok)
           |> Map.fetch!("entries")
           |> Enum.map(& &1["id"]) == [30_220]

    assert authenticated_conn_for("walex")
           |> get(~p"/api/customers?search=0199")
           |> json_response(:ok)
           |> Map.fetch!("entries")
           |> Enum.map(& &1["id"]) == [30_220]
  end

  test "creates a customer with identity, contact, and wholesale details", %{walex_conn: conn} do
    customer =
      conn
      |> post(~p"/api/customers", %{
        "name" => "WHOLESALE CUSTOMER",
        "document_id" => "132-12345-6",
        "address" => "123 Main Street",
        "celphone" => "809-555-0100",
        "email" => "wholesale@example.test",
        "is_wholesaler" => true
      })
      |> json_response(:created)

    assert customer["document_id"] == "132-12345-6"
    assert customer["address"] == "123 Main Street"
    assert customer["celphone"] == "809-555-0100"
    assert customer["wholesaler"] == 1
    assert customer["is_wholesaler"]
  end

  test "updates a customer with identity, contact, and wholesale details", %{walex_conn: conn} do
    customer =
      conn
      |> patch(~p"/api/customers/30218", %{
        "name" => "UPDATED CUSTOMER",
        "document_id" => "402-12345-6",
        "address" => "456 Main Street",
        "celphone" => "809-555-0145",
        "email" => "updated@example.test",
        "is_wholesaler" => true
      })
      |> json_response(:ok)

    assert customer["name"] == "UPDATED CUSTOMER"
    assert customer["document_id"] == "402-12345-6"
    assert customer["address"] == "456 Main Street"
    assert customer["celphone"] == "809-555-0145"
    assert customer["email"] == "updated@example.test"
    assert customer["wholesaler"] == 1
    assert customer["is_wholesaler"]
  end

  defp token_for(name) do
    {:ok, user} =
      Accounts.create_user(%{
        "name" => name,
        "email" => "#{name}-#{System.unique_integer([:positive])}@example.test",
        "tenant" => @tenant,
        "password" => "a-long-test-password"
      })

    {:ok, token} = Accounts.create_user_token(%{"user_id" => user.id})
    {:ok, Accounts.encode_session_token(token)}
  end

  defp authenticated_conn_for(name) do
    {:ok, token} = token_for(name)
    authenticated_conn(token)
  end

  defp authenticated_conn(token),
    do: build_conn() |> put_req_header("authorization", "Bearer #{token}")
end
