defmodule TigooServerWeb.SaleControllerTest do
  use TigooServerWeb.ConnCase, async: false

  import Ecto.Query

  alias TigooServer.Accounts
  alias TigooServer.InventoryEvents
  alias TigooServer.Repo

  alias TigooServer.Retaily.{
    Client,
    Inventory,
    PricingList,
    Product,
    Sale,
    SaleLine,
    SalePaid,
    Sequence,
    Store,
    User,
    UserStore
  }

  @tenant "sales_seed_test"
  @prefix "sales_seed_test"
  @other_tenant "sales_other_test"
  @other_prefix "sales_other_test"

  setup do
    Process.delete(:current_tenant)
    seed_retaily_rows()
    Repo.insert!(%User{id: 1, username: "walex", is_active: 1}, prefix: @other_prefix)

    {:ok, walex_token} = token_for("walex")
    {:ok, no_store_token} = token_for("no_store")
    {:ok, other_tenant_token} = token_for("walex", @other_tenant)

    %{
      walex_conn: authenticated_conn(walex_token),
      no_store_conn: authenticated_conn(no_store_token),
      other_tenant_conn: authenticated_conn(other_tenant_token)
    }
  end

  test "creates the paid discounted delivery sale from 363886", %{walex_conn: conn} do
    before_quantity = inventory_quantity(19_463)
    Phoenix.PubSub.subscribe(TigooServer.PubSub, InventoryEvents.topic(@tenant, 2))
    sale = create_delivery_sale(conn)

    assert sale["invoice_status"] == "close"
    assert sale["due_balance"] in ["0", "0.00"]
    assert inventory_quantity(19_463) == before_quantity - 1

    assert Repo.aggregate(from(line in SaleLine, where: line.sale_id == ^sale["id"]), :count,
             prefix: @prefix
           ) == 1

    assert Repo.aggregate(
             from(payment in SalePaid, where: payment.sale_id == ^sale["id"]),
             :count,
             prefix: @prefix
           ) == 1

    header = Repo.get!(Sale, sale["id"], prefix: @prefix)
    assert header.amount == Decimal.new("3290.00")
    assert header.discount == Decimal.new("110.00")
    assert header.delivery_charge == Decimal.new("200.00")
    assert_receive {:inventory_changed, %{type: "inventory_changed", product_ids: [19_463]}}

    quantities =
      authenticated_conn_for("walex")
      |> get(~p"/api/inventory?store_id=2&product_ids=19463")
      |> json_response(:ok)

    assert quantities == %{
             "entries" => [%{"product_id" => 19_463, "quantity" => before_quantity - 1}]
           }
  end

  test "creates, pays, and closes the credit sale from 363873", %{walex_conn: conn} do
    before_quantity = inventory_quantity(19_203)

    response =
      conn
      |> post(~p"/api/sales", credit_sale_payload())
      |> json_response(:created)

    sale_id = response["id"]
    assert response["invoice_status"] == "open"
    assert response["due_date"] == tomorrow()

    assert Repo.aggregate(from(payment in SalePaid, where: payment.sale_id == ^sale_id), :count,
             prefix: @prefix
           ) == 0

    assert inventory_quantity(19_203) == before_quantity - 1

    paid =
      authenticated_conn_for("walex")
      |> post(~p"/api/sales/#{sale_id}/payments", %{amount: "200", type: "CASH"})
      |> json_response(:ok)

    assert paid["invoice_status"] == "close"
    assert paid["due_balance"] in ["0", "0.00"]
  end

  test "requires credit sale due dates to be in the future", %{walex_conn: conn} do
    assert conn
           |> post(~p"/api/sales", Map.delete(credit_sale_payload(), :due_date))
           |> json_response(:unprocessable_entity) == %{
             "errors" => %{"due_date" => ["can't be blank"]}
           }

    assert authenticated_conn_for("walex")
           |> post(~p"/api/sales", %{credit_sale_payload() | due_date: today()})
           |> json_response(:unprocessable_entity) == %{
             "errors" => %{"due_date" => ["must be a future date"]}
           }
  end

  test "derives totals for the multiple-line sale from 363885", %{walex_conn: conn} do
    before_quantities = inventory_quantities([8_679, 19_383])

    response =
      conn
      |> post(~p"/api/sales", multiple_line_sale_payload())
      |> json_response(:created)

    assert response["invoice_status"] == "close"

    sale = Repo.get!(Sale, response["id"], prefix: @prefix)
    assert sale.amount == Decimal.new("1830.00")
    assert sale.discount == Decimal.new("200.00")

    assert Repo.aggregate(from(line in SaleLine, where: line.sale_id == ^sale.id), :count,
             prefix: @prefix
           ) == 2

    assert inventory_quantity(8_679) == before_quantities[8_679] - 1
    assert inventory_quantity(19_383) == before_quantities[19_383] - 1
  end

  test "cancellation is idempotent and restores stock", %{walex_conn: conn} do
    before_quantity = inventory_quantity(19_463)
    sale = create_delivery_sale(conn)
    assert inventory_quantity(19_463) == before_quantity - 1

    Phoenix.PubSub.subscribe(TigooServer.PubSub, InventoryEvents.topic(@tenant, 2))

    cancelled =
      authenticated_conn_for("walex")
      |> post(~p"/api/sales/#{sale["id"]}/cancel")
      |> json_response(:ok)

    assert cancelled["status"] == "RETURN"
    assert cancelled["invoice_status"] == "cancelled"
    assert inventory_quantity(19_463) == before_quantity
    assert_receive {:inventory_changed, %{type: "inventory_changed", product_ids: [19_463]}}

    quantities =
      authenticated_conn_for("walex")
      |> get(~p"/api/inventory?store_id=2&product_ids=19463")
      |> json_response(:ok)

    assert quantities == %{
             "entries" => [%{"product_id" => 19_463, "quantity" => before_quantity}]
           }

    again =
      authenticated_conn_for("walex")
      |> post(~p"/api/sales/#{sale["id"]}/cancel")
      |> json_response(:ok)

    assert again["id"] == sale["id"]
    assert inventory_quantity(19_463) == before_quantity

    assert Repo.aggregate(from(line in SaleLine, where: line.sale_id == ^sale["id"]), :count,
             prefix: @prefix
           ) == 1

    assert Repo.aggregate(
             from(payment in SalePaid, where: payment.sale_id == ^sale["id"]),
             :count,
             prefix: @prefix
           ) == 1
  end

  test "backorders decrement low and negative inventory", %{walex_conn: conn} do
    before_sequence = Repo.get_by!(Sequence, [code: "DV"], prefix: @prefix).current_seq
    before_quantity = inventory_quantity(19_463)
    before_negative_quantity = inventory_quantity(19_385)

    low_stock_sale =
      conn
      |> post(
        ~p"/api/sales",
        delivery_sale_payload(%{
          lines: [%{product_id: 19_463, quantity: 13, discount: "0"}],
          payments: []
        })
      )
      |> json_response(:created)

    assert low_stock_sale["invoice_status"] == "open"
    assert inventory_quantity(19_463) == before_quantity - 13

    assert Repo.get_by!(Sequence, [code: "DV"], prefix: @prefix).current_seq ==
             before_sequence + 1

    assert Repo.aggregate(Sale, :count, prefix: @prefix) == 1
    assert Repo.aggregate(SaleLine, :count, prefix: @prefix) == 1
    assert Repo.aggregate(SalePaid, :count, prefix: @prefix) == 0

    negative_stock_sale =
      authenticated_conn_for("walex")
      |> post(
        ~p"/api/sales",
        delivery_sale_payload(%{
          lines: [%{product_id: 19_385, quantity: 1, discount: "0"}],
          payments: []
        })
      )
      |> json_response(:created)

    assert negative_stock_sale["invoice_status"] == "open"
    assert inventory_quantity(19_385) == before_negative_quantity - 1

    assert Repo.get_by!(Sequence, [code: "DV"], prefix: @prefix).current_seq ==
             before_sequence + 2
  end

  test "requires a tenant scope and enforces tenant and assigned-store isolation", %{
    no_store_conn: no_store_conn,
    other_tenant_conn: other_tenant_conn
  } do
    assert build_conn() |> get(~p"/api/sales") |> response(:unauthorized)

    assert no_store_conn
           |> post(~p"/api/sales", delivery_sale_payload())
           |> response(:forbidden)

    assert no_store_conn |> get(~p"/api/sales?store_id=2") |> json_response(:ok) == %{
             "entries" => []
           }

    assert other_tenant_conn |> get(~p"/api/sales") |> json_response(:ok) == %{"entries" => []}
  end

  # ---------------------------------------------------------------------------
  # Additional checkout scenarios
  # ---------------------------------------------------------------------------

  test "cashier creates and pays a new in-store sale", %{walex_conn: conn} do
    before_quantity = inventory_quantity(19_383)

    response =
      conn
      |> post(~p"/api/sales", %{
        store_id: 2,
        client_id: 30_218,
        sequence_type: "DV",
        status: "CASH",
        sale_type: "IN_SHOP",
        delivery_charge: "0",
        lines: [%{product_id: 19_383, quantity: 1, discount: "0"}],
        payments: [%{amount: "230", type: "CASH"}]
      })
      |> json_response(:created)

    assert response["client"]["id"] == 30_218
    assert response["invoice_status"] == "close"
    assert response["total_paid"] in ["230", "230.00"]
    assert response["due_balance"] in ["0", "0.00"]
    assert inventory_quantity(19_383) == before_quantity - 1

    assert Repo.aggregate(from(line in SaleLine, where: line.sale_id == ^response["id"]), :count,
             prefix: @prefix
           ) == 1

    assert Repo.aggregate(
             from(payment in SalePaid, where: payment.sale_id == ^response["id"]),
             :count,
             prefix: @prefix
           ) == 1
  end

  test "persists a trimmed optional memo and rejects a memo over 1000 characters", %{
    walex_conn: conn
  } do
    response =
      conn
      |> post(
        ~p"/api/sales",
        delivery_sale_payload(%{
          additional_info: "  Leave at the side entrance.\nCall on arrival.  "
        })
      )
      |> json_response(:created)

    assert response["additional_info"] == "Leave at the side entrance.\nCall on arrival."

    assert Repo.get!(Sale, response["id"], prefix: @prefix).additional_info ==
             "Leave at the side entrance.\nCall on arrival."

    assert authenticated_conn_for("walex")
           |> post(
             ~p"/api/sales",
             delivery_sale_payload(%{additional_info: String.duplicate("a", 1001)})
           )
           |> json_response(:unprocessable_entity) == %{
             "errors" => %{"additional_info" => ["should be at most %{count} character(s)"]}
           }
  end

  test "uses the default price-list price for the sale total", %{walex_conn: conn} do
    Repo.insert!(%PricingList{price: 2_300.0, product_id: 8_679, pricing_id: 1}, prefix: @prefix)

    response =
      conn
      |> post(~p"/api/sales", %{
        store_id: 2,
        client_id: 24_181,
        sequence_type: "CF",
        status: "CASH",
        sale_type: "IN_SHOP",
        delivery_charge: "0",
        lines: [%{product_id: 8_679, quantity: 1, discount: "0"}],
        payments: [%{amount: "2300", type: "CASH"}]
      })
      |> json_response(:created)

    assert response["amount"] in ["2300", "2300.00"]
    assert response["total_paid"] in ["2300", "2300.00"]
    assert response["invoice_status"] == "close"
  end

  test "treats an overpayment as change instead of a negative invoice balance", %{
    walex_conn: conn
  } do
    response =
      conn
      |> post(~p"/api/sales", %{
        store_id: 2,
        client_id: 30_218,
        sequence_type: "DV",
        status: "CASH",
        sale_type: "IN_SHOP",
        delivery_charge: "0",
        lines: [%{product_id: 19_383, quantity: 1, discount: "0"}],
        payments: [%{amount: "250", type: "CASH"}]
      })
      |> json_response(:created)

    assert response["total_paid"] in ["250", "250.00"]
    assert response["due_balance"] in ["0", "0.00"]
    assert response["invoice_status"] == "close"
  end

  test "settles a ten-product credit sale with payments on different days", %{walex_conn: conn} do
    before_quantities = inventory_quantities(Enum.map(large_credit_sale_lines(), & &1.product_id))

    sale =
      conn
      |> post(~p"/api/sales", large_credit_sale_payload())
      |> json_response(:created)

    sale_id = sale["id"]
    assert sale["invoice_status"] == "open"

    assert Repo.aggregate(from(line in SaleLine, where: line.sale_id == ^sale_id), :count,
             prefix: @prefix
           ) == 10

    paid =
      [{10_000, "CASH"}, {8_000, "CC"}, {7_155, "CASH"}]
      |> Enum.map(fn {amount, type} ->
        authenticated_conn_for("walex")
        |> post(~p"/api/sales/#{sale_id}/payments", %{amount: to_string(amount), type: type})
        |> json_response(:ok)
      end)

    Enum.zip(
      Repo.all(
        from(payment in SalePaid, where: payment.sale_id == ^sale_id, order_by: payment.id),
        prefix: @prefix
      ),
      [~N[2026-08-10 10:00:00], ~N[2026-08-12 10:00:00], ~N[2026-08-15 10:00:00]]
    )
    |> Enum.each(fn {payment, date} ->
      Repo.update_all(
        from(entry in SalePaid, where: entry.id == ^payment.id),
        [set: [date_create: date]],
        prefix: @prefix
      )
    end)

    assert List.last(paid)["invoice_status"] == "close"
    assert List.last(paid)["due_balance"] in ["0", "0.00"]

    assert Repo.all(
             from(payment in SalePaid,
               where: payment.sale_id == ^sale_id,
               order_by: payment.date_create,
               select: payment.date_create
             ),
             prefix: @prefix
           ) == [~N[2026-08-10 10:00:00], ~N[2026-08-12 10:00:00], ~N[2026-08-15 10:00:00]]

    assert Repo.all(
             from(payment in SalePaid,
               where: payment.sale_id == ^sale_id,
               order_by: payment.date_create,
               select: payment.type
             ),
             prefix: @prefix
           ) == ["CASH", "CC", "CASH"]

    Enum.each(large_credit_sale_lines(), fn line ->
      assert inventory_quantity(line.product_id) ==
               before_quantities[line.product_id] - line.quantity
    end)
  end

  test "cancels the July 2026 invoice pattern from sale 363261 with stock restoration", %{
    walex_conn: conn
  } do
    product_ids = [19_509, 19_378, 8_694, 19_553]
    before_quantities = inventory_quantities(product_ids)

    sale =
      conn
      |> post(~p"/api/sales", july_return_sale_payload())
      |> json_response(:created)

    assert sale["invoice_status"] == "close"
    assert inventory_quantity(19_509) == before_quantities[19_509] - 1
    assert inventory_quantity(19_378) == before_quantities[19_378] - 1
    assert inventory_quantity(8_694) == before_quantities[8_694] - 1
    assert inventory_quantity(19_553) == before_quantities[19_553] - 2

    cancelled =
      authenticated_conn_for("walex")
      |> post(~p"/api/sales/#{sale["id"]}/cancel")
      |> json_response(:ok)

    assert cancelled["status"] == "RETURN"

    Enum.each(product_ids, fn product_id ->
      assert inventory_quantity(product_id) == before_quantities[product_id]
    end)
  end

  defp create_delivery_sale(conn) do
    conn
    |> post(~p"/api/sales", delivery_sale_payload())
    |> json_response(:created)
  end

  defp delivery_sale_payload(overrides \\ %{}) do
    Map.merge(
      %{
        store_id: 2,
        client_id: 30_218,
        sequence_type: "DV",
        status: "CASH",
        sale_type: "FOR_DELIVER",
        delivery_charge: "200",
        lines: [%{product_id: 19_463, quantity: 1, discount: "110"}],
        payments: [%{amount: "3290", type: "CASH"}]
      },
      overrides
    )
  end

  defp credit_sale_payload do
    %{
      store_id: 2,
      client_id: 26_623,
      sequence_type: "CF",
      status: "CREDIT",
      due_date: tomorrow(),
      sale_type: "IN_SHOP",
      delivery_charge: "0",
      lines: [%{product_id: 19_203, quantity: 1, discount: "40"}],
      payments: []
    }
  end

  defp multiple_line_sale_payload do
    %{
      store_id: 2,
      client_id: 24_181,
      sequence_type: "CF",
      status: "CASH",
      sale_type: "IN_SHOP",
      delivery_charge: "0",
      lines: [
        %{product_id: 8_679, quantity: 1, discount: "200"},
        %{product_id: 19_383, quantity: 1, discount: "0"}
      ],
      payments: [%{amount: "1830", type: "CASH"}]
    }
  end

  # Product IDs and default prices were read from the seeded tenant's
  # app_inventory/product/pricing_list records for store 2.
  defp large_credit_sale_payload do
    %{
      store_id: 2,
      client_id: 30_218,
      sequence_type: "CF",
      status: "CREDIT",
      due_date: tomorrow(),
      sale_type: "IN_SHOP",
      delivery_charge: "0",
      payments: [],
      lines: large_credit_sale_lines()
    }
  end

  defp today, do: Date.utc_today() |> Date.to_iso8601()
  defp tomorrow, do: Date.utc_today() |> Date.add(1) |> Date.to_iso8601()

  defp large_credit_sale_lines do
    [
      %{product_id: 19_023, quantity: 5, discount: "0"},
      %{product_id: 19_507, quantity: 6, discount: "0"},
      %{product_id: 19_243, quantity: 7, discount: "0"},
      %{product_id: 19_553, quantity: 8, discount: "0"},
      %{product_id: 19_203, quantity: 9, discount: "0"},
      %{product_id: 19_558, quantity: 10, discount: "0"},
      %{product_id: 19_508, quantity: 11, discount: "0"},
      %{product_id: 19_563, quantity: 12, discount: "0"},
      %{product_id: 19_343, quantity: 13, discount: "0"},
      %{product_id: 19_527, quantity: 14, discount: "0"}
    ]
  end

  defp july_return_sale_payload do
    # July 31, 2026 sale 363261: VEN00000024473, customer 30190, store 2.
    %{
      store_id: 2,
      client_id: 30_190,
      sequence_type: "DV",
      status: "CASH",
      sale_type: "IN_SHOP",
      delivery_charge: "300",
      payments: [%{amount: "4200", type: "CASH"}],
      lines: [
        %{product_id: 19_509, quantity: 1, discount: "400"},
        %{product_id: 19_378, quantity: 1, discount: "100"},
        %{product_id: 8_694, quantity: 1, discount: "650"},
        %{product_id: 19_553, quantity: 2, discount: "260"}
      ]
    }
  end

  defp seed_retaily_rows do
    prefix = @prefix
    Repo.insert!(%Store{id: 2, name: "SEED STORE"}, prefix: prefix)
    walex = Repo.insert!(%User{id: 1, username: "walex", is_active: 1}, prefix: prefix)
    no_store = Repo.insert!(%User{id: 2, username: "no_store", is_active: 1}, prefix: prefix)
    Repo.insert!(%UserStore{user_id: walex.id, store_id: 2}, prefix: prefix)
    _ = no_store

    Enum.each(
      [
        {26_623, "CREDIT CLIENT"},
        {24_181, "MULTI LINE CLIENT"},
        {30_190, "JULY RETURN CLIENT"},
        {30_218, "SCOLNY REYES"}
      ],
      fn {id, name} ->
        Repo.insert!(%Client{id: id, name: name}, prefix: prefix)
      end
    )

    Enum.each(
      [
        {8_679, 1800, 10},
        {19_203, 240, 265},
        {19_383, 230, 10},
        {19_385, 300, -144},
        {19_463, 3200, 12},
        {19_023, 175, 25},
        {19_507, 160, 25},
        {19_243, 210, 25},
        {19_553, 130, 25},
        {19_558, 275, 25},
        {19_508, 240, 25},
        {19_563, 230, 25},
        {19_343, 700, 25},
        {19_527, 100, 25},
        {19_509, 1600, 25},
        {19_378, 250, 25},
        {8_694, 3200, 25}
      ],
      fn {id, price, quantity} ->
        Repo.insert!(%Product{id: id, name: "SEED #{id}", active: 1}, prefix: prefix)

        Repo.insert!(%PricingList{price: price * 1.0, product_id: id, pricing_id: 1},
          prefix: prefix
        )

        Repo.insert!(
          %Inventory{
            product_id: id,
            store_id: 2,
            prev_quantity: quantity,
            quantity: quantity,
            next_quantity: quantity
          },
          prefix: prefix
        )
      end
    )

    Repo.insert!(
      %Sequence{
        id: 1,
        name: "CONSUMIDOR FINAL",
        code: "CF",
        prefix: "B02",
        fill: 6,
        increment_by: 1,
        current_seq: 35_700
      },
      prefix: prefix
    )

    Repo.insert!(
      %Sequence{
        id: 3,
        name: "DIARIO DE VENTAS",
        code: "DV",
        prefix: "VEN",
        fill: 9,
        increment_by: 1,
        current_seq: 24_897
      },
      prefix: prefix
    )
  end

  defp token_for(name, tenant \\ @tenant) do
    {:ok, user} =
      Accounts.create_user(%{
        "name" => name,
        "email" => "#{name}-#{System.unique_integer([:positive])}@example.test",
        "tenant" => tenant,
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

  defp inventory_quantity(product_id),
    do: Repo.get_by!(Inventory, [product_id: product_id, store_id: 2], prefix: @prefix).quantity

  defp inventory_quantities(product_ids) do
    product_ids
    |> Enum.map(&{&1, inventory_quantity(&1)})
    |> Map.new()
  end
end
