defmodule TigooServer.Fe.SaleFiscal do
  @moduledoc "Fiscal pricing for the existing 18%-inclusive POS catalog."
  @codes ~w(TEST_E31 TEST_E32 TEST_E44 TEST_E45 TEST_E46)
  def codes, do: @codes
  def indicator("TEST_E44", _), do: "4"
  def indicator("TEST_E46", _), do: "3"
  def indicator(_, requested), do: requested || "1"
  def factor("1"), do: Decimal.new("1.18")
  def factor("2"), do: Decimal.new("1.16")
  def factor(_), do: Decimal.new(1)

  def decimal(%Decimal{} = value), do: value
  def decimal(value) when is_float(value), do: Decimal.from_float(value) |> Decimal.round(2)
  def decimal(value), do: Decimal.new(value)

  def price(catalog_price, code, requested) do
    catalog_price |> decimal() |> Decimal.div(Decimal.new("1.18"))
    |> Decimal.mult(factor(indicator(code, requested))) |> Decimal.round(2)
  end

  def amounts(lines) do
    groups = Enum.group_by(lines, & &1.tax)
    Enum.reduce(groups, %{amount: Decimal.new(0), sub: Decimal.new(0), tax: Decimal.new(0), groups: %{}}, fn {indicator, items}, totals ->
      gross = Enum.reduce(items, Decimal.new(0), fn line, sum ->
        amount = Decimal.mult(line.price, line.quantity) |> Decimal.sub(line.discount) |> Decimal.round(2)
        Decimal.add(sum, amount)
      end)
      base = Decimal.div(gross, factor(indicator)) |> Decimal.round(2)
      vat = Decimal.sub(gross, base)
      %{amount: Decimal.add(totals.amount, gross), sub: Decimal.add(totals.sub, base),
        tax: Decimal.add(totals.tax, vat), groups: Map.put(totals.groups, indicator, %{base: base, tax: vat})}
    end)
  end
end
