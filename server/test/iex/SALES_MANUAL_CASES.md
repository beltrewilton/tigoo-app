# Manual IEx sales cases

This runbook targets a tenant you select. It writes real sales, payments, and inventory; use a controlled test customer/products or reverse every manual sale afterward.

Start IEx from `server`:

```bash
bash sh/local_run.sh 
```

Paste the shared setup in every new IEx session, then execute cases 1, 3, 7, 8, 9, and 10 in order as needed. Do not run a case before `TenantContext.tenant!()` returns the selected tenant.

```elixir
alias TigooServer.{Repo, TenantContext}
alias TigooServer.Retaily.{Inventory, Sale, SaleLine, SalePaid, Sales, Sequence}
import Ecto.Query

tenant = "your_tenant"
prefix = Triplex.to_prefix(tenant)
TenantContext.put_tenant(tenant)
^tenant = TenantContext.tenant!()
scope = %{user: %{name: "walex"}}

stock = fn product_id ->
  Repo.get_by!(Inventory, [product_id: product_id, store_id: 2], prefix: prefix).quantity
end

stocks = fn product_ids -> Map.new(product_ids, &{&1, stock.(&1)}) end
assert = fn true, _message -> :ok; false, message -> raise message end
```

## Case 1 — paid in-store sale with live tenant data

```elixir
before_19507 = stock.(19_507)
before_dv = Repo.get_by!(Sequence, [code: "DV"], prefix: prefix)

expected_dv_current = before_dv.current_seq + before_dv.increment_by
expected_dv_sequence =
  String.pad_trailing(before_dv.prefix, before_dv.fill, "0") <>
    Integer.to_string(expected_dv_current)

{:ok, case1} =
  Sales.create_sale(scope, %{
    store_id: 2, client_id: 30_218, sequence_type: "DV", status: "CASH",
    sale_type: "IN_SHOP", delivery_charge: "0",
    lines: [%{product_id: 19_507, quantity: 1, discount: "0"}],
    payments: [%{amount: "160", type: "CASH"}]
  })

assert.(case1.invoice_status == "close", "case 1 must close")
assert.(stock.(19_507) == before_19507 - 1, "case 1 stock mismatch")

after_dv = Repo.get_by!(Sequence, [code: "DV"], prefix: prefix)
assert.(after_dv.current_seq == expected_dv_current, "DV sequence increment mismatch")
assert.(case1.sequence_type == "DV", "case 1 sequence type mismatch")
assert.(case1.sequence == expected_dv_sequence, "issued DV sequence mismatch")
case1
```

## Case 3 — two-line paid sale with live tenant data

```elixir
before_case3 = stocks.([19_553, 19_203])

{:ok, case3} =
  Sales.create_sale(scope, %{
    store_id: 2, client_id: 30_218, sequence_type: "CF", status: "CASH",
    sale_type: "IN_SHOP", delivery_charge: "0",
    lines: [
      %{product_id: 19_553, quantity: 1, discount: "0"},
      %{product_id: 19_203, quantity: 1, discount: "0"}
    ],
    payments: [%{amount: "370", type: "CASH"}]
  })

assert.(case3.amount == Decimal.new("370.00"), "case 3 amount mismatch")
assert.(stock.(19_553) == before_case3[19_553] - 1, "case 3 product 19553 stock mismatch")
assert.(stock.(19_203) == before_case3[19_203] - 1, "case 3 product 19203 stock mismatch")
case3
```

## Case 7 — simple paid checkout

```elixir
before_19558 = stock.(19_558)

{:ok, case7} =
  Sales.create_sale(scope, %{
    store_id: 2, client_id: 30_218, sequence_type: "DV", status: "CASH",
    sale_type: "IN_SHOP", delivery_charge: "0",
    lines: [%{product_id: 19_558, quantity: 1, discount: "0"}],
    payments: [%{amount: "275", type: "CASH"}]
  })

assert.(case7.invoice_status == "close", "case 7 must close")
assert.(stock.(19_558) == before_19558 - 1, "case 7 stock mismatch")
case7
```

## Case 8 — ten products, partial CASH/CC payments on different days

```elixir
case8_lines = [
  %{product_id: 19_507, quantity: 5, discount: "0"},
  %{product_id: 19_553, quantity: 6, discount: "0"},
  %{product_id: 19_203, quantity: 7, discount: "0"},
  %{product_id: 19_558, quantity: 8, discount: "0"},
  %{product_id: 19_508, quantity: 9, discount: "0"},
  %{product_id: 19_563, quantity: 10, discount: "0"},
  %{product_id: 19_343, quantity: 11, discount: "0"},
  %{product_id: 19_527, quantity: 12, discount: "0"},
  %{product_id: 19_359, quantity: 13, discount: "0"},
  %{product_id: 19_378, quantity: 14, discount: "0"}
]

before_case8 = stocks.(Enum.map(case8_lines, & &1.product_id))

{:ok, case8} =
  Sales.create_sale(scope, %{
    store_id: 2, client_id: 30_218, sequence_type: "CF", status: "CREDIT",
    sale_type: "IN_SHOP", delivery_charge: "0", lines: case8_lines, payments: []
  })

assert.(case8.invoice_status == "open", "case 8 must start open")
assert.(case8.amount == Decimal.new("69820.00"), "case 8 amount mismatch")

{:ok, _} = Sales.add_payment(scope, case8.id, %{amount: "10000", type: "CASH"})
{:ok, _} = Sales.add_payment(scope, case8.id, %{amount: "20000", type: "CC"})
{:ok, case8_paid} = Sales.add_payment(scope, case8.id, %{amount: "39820", type: "CASH"})

payment_dates = [~N[2026-08-10 10:00:00], ~N[2026-08-12 10:00:00], ~N[2026-08-15 10:00:00]]

Repo.all(from(payment in SalePaid, where: payment.sale_id == ^case8.id, order_by: payment.id), prefix: prefix)
|> Enum.zip(payment_dates)
|> Enum.each(fn {payment, date} ->
  Repo.update_all(from(entry in SalePaid, where: entry.id == ^payment.id), [set: [date_create: date]], prefix: prefix)
end)

assert.(case8_paid.invoice_status == "close", "case 8 must close")
Enum.each(case8_lines, fn line ->
  assert.(stock.(line.product_id) == before_case8[line.product_id] - line.quantity, "case 8 stock mismatch for #{line.product_id}")
end)
case8_paid
```

## Case 9 — July 2026 return pattern (`363217`)

```elixir
case9_products = [19_378, 19_317]
before_case9 = stocks.(case9_products)

{:ok, case9} =
  Sales.create_sale(scope, %{
    store_id: 2, client_id: 30_185, sequence_type: "CF", status: "CASH",
    sale_type: "IN_SHOP", delivery_charge: "300",
    lines: [
      %{product_id: 19_378, quantity: 1, discount: "50"},
      %{product_id: 19_317, quantity: 1, discount: "400"}
    ],
    payments: [%{amount: "4950", type: "CASH"}]
  })

assert.(stock.(19_378) == before_case9[19_378] - 1, "case 9 product 19378 stock mismatch")
assert.(stock.(19_317) == before_case9[19_317] - 1, "case 9 product 19317 stock mismatch")

{:ok, case9_cancelled} = Sales.cancel_sale(scope, case9.id)
assert.(case9_cancelled.status == "RETURN", "case 9 must return")
Enum.each(case9_products, fn product_id ->
  assert.(stock.(product_id) == before_case9[product_id], "case 9 restock mismatch for #{product_id}")
end)
case9_cancelled
```

## Case 10 — sell the last unit in inventory

Product `8679` (`MULTIVITAMINICO PLATINUM MUSCLETECH`) is active, priced at `1000`, and has one unit in store `2`. Run this once only: the expected final inventory is zero.

```elixir
before_8679 = stock.(8_679)
assert.(before_8679 == 1, "case 10 requires exactly one unit of product 8679")

{:ok, case10} =
  Sales.create_sale(scope, %{
    store_id: 2, client_id: 30_218, sequence_type: "DV", status: "CASH",
    sale_type: "IN_SHOP", delivery_charge: "0",
    lines: [%{product_id: 8_679, quantity: 1, discount: "0"}],
    payments: [%{amount: "1000", type: "CASH"}]
  })

assert.(case10.invoice_status == "close", "case 10 must close")
assert.(stock.(8_679) == 0, "case 10 must leave product 8679 at zero")
case10
```
