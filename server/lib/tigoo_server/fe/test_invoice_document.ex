defmodule TigooServer.Fe.TestInvoiceDocument do
  @moduledoc "POS sale snapshots mapped to DGII E31/E32/E44/E45/E46 schemas."
  alias TigooServer.Fe.Generation.{Document, Rules, Schema}
  alias TigooServer.Fe.SaleFiscal, as: Fiscal

  def validate(invoice) do
    row = row(invoice)
    info = Rules.check!(row, invoice.issuer_rnc)
    built = Document.build_ecf!(row, Schema.load!(info.type, []))
    Rules.check_document!(row, built.tree)
    Rules.check_adjustments!(row, built.tree)
    case Rules.observations(built.tree) do
      [] -> :ok
      _ -> {:error, "Invoice arithmetic does not balance"}
    end
  rescue
    error in [TigooServer.Fe.Generation.Error, ArgumentError] -> {:error, Exception.message(error)}
    _ -> {:error, "Review eCF buyer identification and invoice amounts"}
  end

  def totals(snapshot) do
    snapshot = snapshot |> Jason.encode!() |> Jason.decode!()
    snapshot |> document_lines() |> Fiscal.amounts() |> Map.take([:amount, :sub, :tax])
  end

  def row(invoice) do
    s = invoice.snapshot
    type = String.slice(invoice.encf, 1, 2)
    unless ("TEST_E" <> type) in Fiscal.codes(), do: raise(ArgumentError, "Unsupported POS sale type")
    details = s["ecf"] || %{}
    lines = document_lines(s)
    amounts = Fiscal.amounts(lines)
    unless Decimal.equal?(amounts.amount, Fiscal.decimal(s["totals"]["amount"])),
      do: raise(ArgumentError, "Round checkout amounts to cents before issuing the eCF")
    fields = %{"Version" => "1.0", "TipoeCF" => type, "ENCF" => invoice.encf,
      "TipoIngresos" => details["ecf_income_type"] || "01",
      "TipoPago" => if(s["status"] == "CREDIT", do: "2", else: "1"),
      "RNCEmisor" => invoice.issuer_rnc, "RazonSocialEmisor" => s["issuer_name"],
      "DireccionEmisor" => s["issuer_address"], "FechaEmision" => date(s["issued_on"])}
    fields = if type != "32", do: Map.put(fields, "FechaVencimientoSecuencia", date(s["sequence_expiry"])), else: fields
    fields = if type in ~w(31 32 45) and Enum.any?(lines, &(&1.tax in ~w(1 2))),
      do: Map.put(fields, "IndicadorMontoGravado", "1"), else: fields
    fields = if s["due_date"], do: Map.put(fields, "FechaLimitePago", date(s["due_date"])), else: fields
    fields = fields |> buyer_fields(s, type, amounts.amount) |> payment_fields(s, amounts.amount)
    fields = lines |> Enum.with_index(1) |> Enum.reduce(fields, fn {line, index}, acc ->
      values = %{"NumeroLinea" => to_string(index), "IndicadorFacturacion" => line.tax,
        "NombreItem" => String.slice(line.name, 0, 80), "IndicadorBienoServicio" => line.service,
        "CantidadItem" => to_string(line.quantity), "PrecioUnitarioItem" => money(line.price),
        "MontoItem" => money(Decimal.sub(Decimal.mult(line.price, line.quantity), line.discount))}
      values = if Decimal.positive?(line.discount), do: Map.put(values, "DescuentoMonto", money(line.discount)), else: values
      acc = Enum.reduce(values, acc, fn {key, value}, result -> Map.put(result, "#{key}[#{index}]", value) end)
      if Decimal.positive?(line.discount) do
        acc |> Map.put("TipoSubDescuento[#{index}][1]", "$")
          |> Map.put("MontoSubDescuento[#{index}][1]", money(line.discount))
      else
        acc
      end
    end)
    fields = total_fields(fields, amounts)
    %{number: 1, fields: fields, cells: Map.new(fields, fn {key, value} -> {key, %{value: value, coordinate: "POS:#{key}"}} end)}
  end

  defp buyer_fields(fields, s, type, amount) do
    d = s["ecf"] || %{}
    buyer = s["client"]
    kind = d["ecf_buyer_kind"] || "domestic"
    id = present(d["ecf_buyer_id"]) || present(buyer["document_id"])
    name = present(d["ecf_buyer_name"]) || present(buyer["name"])
    unless name && String.length(name) <= 150, do: raise(ArgumentError, "Buyer legal name is required (maximum 150 characters)")
    unless kind in ~w(domestic foreign), do: raise(ArgumentError, "Choose domestic or foreign buyer identification")
    if kind == "foreign" and type in ~w(31 45), do: raise(ArgumentError, "This sale type requires the buyer RNC/cédula")
    required? = type in ~w(31 44 45 46) or Decimal.compare(amount, 250_000) != :lt
    id = if kind == "domestic" and id, do: String.replace(id, ~r/[\s-]/, ""), else: id
    valid? = if kind == "domestic", do: is_binary(id) and Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, id),
      else: is_binary(id) and String.length(id) in 1..20
    if required? and not valid?, do: raise(ArgumentError, "Provide a valid buyer RNC/cédula or eligible foreign identifier")
    if type in ~w(44 45) and d["ecf_buyer_confirmed"] not in [true, "true"],
      do: raise(ArgumentError, "Confirm that the buyer qualifies for this sale type")
    if type == "46" and d["ecf_export_confirmed"] not in [true, "true"],
      do: raise(ArgumentError, "Confirm that this goods transaction qualifies for an export eCF")
    fields = Map.put(fields, "RazonSocialComprador", name)
    fields = if valid?, do: Map.put(fields, if(kind == "domestic", do: "RNCComprador", else: "IdentificadorExtranjero"), id), else: fields
    address = present(d["ecf_buyer_address"]) || present(buyer["address"])
    fields = if address, do: Map.put(fields, "DireccionComprador", String.slice(address, 0, 100)), else: fields
    if type == "46" do
      country = present(d["ecf_buyer_country"])
      destination = present(d["ecf_destination_country"])
      unless country && destination && String.length(country) <= 60 && String.length(destination) <= 60,
        do: raise(ArgumentError, "Buyer country and destination country are required (maximum 60 characters)")
      Map.merge(fields, %{"PaisComprador" => country, "PaisDestino" => destination})
    else
      fields
    end
  end

  defp payment_fields(fields, %{"status" => "CREDIT"}, _amount), do: fields
  defp payment_fields(fields, s, amount) do
    grouped = Enum.group_by(s["payments"], & &1["type"])
    card = Enum.reduce(grouped["CC"] || [], Decimal.new(0), &Decimal.add(Fiscal.decimal(&1["amount"]), &2))
    cash = Enum.reduce(grouped["CASH"] || [], Decimal.new(0), &Decimal.add(Fiscal.decimal(&1["amount"]), &2))
    if Decimal.compare(card, amount) == :gt or Decimal.compare(Decimal.add(card, cash), amount) == :lt,
      do: raise(ArgumentError, "Payments must cover the invoice; card payments cannot exceed its total")
    # Cash change is excluded from the fiscal payment table.
    payments = [{"3", card}, {"1", Decimal.sub(amount, card)}] |> Enum.filter(fn {_, value} -> Decimal.positive?(value) end)
    payments |> Enum.with_index(1) |> Enum.reduce(fields, fn {{code, value}, index}, result ->
      result |> Map.put("FormaPago[#{index}]", code) |> Map.put("MontoPago[#{index}]", money(value))
    end)
  end

  defp total_fields(fields, amounts) do
    fields = Map.put(fields, "MontoTotal", money(amounts.amount))
    taxable = Map.drop(amounts.groups, ["4"])
    fields = if map_size(taxable) > 0 do
      base = Enum.reduce(taxable, Decimal.new(0), fn {_, values}, sum -> Decimal.add(sum, values.base) end)
      vat = Enum.reduce(taxable, Decimal.new(0), fn {_, values}, sum -> Decimal.add(sum, values.tax) end)
      Map.merge(fields, %{"MontoGravadoTotal" => money(base), "TotalITBIS" => money(vat)})
    else
      fields
    end
    Enum.reduce(amounts.groups, fields, fn
      {"4", values}, result -> Map.put(result, "MontoExento", money(values.base))
      {indicator, values}, result ->
        rate = %{"1" => "18", "2" => "16", "3" => "0"}[indicator]
        result |> Map.put("MontoGravadoI#{indicator}", money(values.base))
          |> Map.put("ITBIS#{indicator}", rate) |> Map.put("TotalITBIS#{indicator}", money(values.tax))
    end)
  end

  defp document_lines(s) do
    code = s["sequence_type"] || "TEST_E32"
    lines = Enum.map(s["lines"], fn l ->
      service = l["kind"] || "1"
      if code == "TEST_E46" and service != "1", do: raise(ArgumentError, "Export eCF checkout supports goods; invoice services separately")
      %{name: l["name"], quantity: l["quantity"], price: Fiscal.decimal(l["price"]),
        discount: Fiscal.decimal(l["discount"]), net: Fiscal.decimal(l["total"]),
        tax: Fiscal.indicator(code, l["tax"]), service: service}
    end)
    net = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.net, &2))
    line_discounts = Enum.reduce(lines, Decimal.new(0), &Decimal.add(&1.discount, &2))
    global = Decimal.sub(Fiscal.decimal(s["totals"]["discount"]), line_discounts)
    {lines, _} = Enum.map_reduce(lines, {global, net}, fn line, {remaining, remaining_net} ->
      if Decimal.positive?(line.net) do
        share = if Decimal.equal?(remaining_net, line.net), do: remaining,
          else: Decimal.div(Decimal.mult(line.net, remaining), remaining_net) |> Decimal.round(2)
        share = share |> Decimal.min(remaining) |> Decimal.min(line.net)
        {%{line | discount: Decimal.add(line.discount, share)},
          {Decimal.sub(remaining, share), Decimal.sub(remaining_net, line.net)}}
      else
        {line, {remaining, remaining_net}}
      end
    end)
    if Decimal.positive?(Fiscal.decimal(s["delivery_charge"])) do
      if code == "TEST_E46", do: raise(ArgumentError, "Separate delivery services must be invoiced separately from exported goods")
      lines ++ [%{name: "Entrega", quantity: 1, price: Fiscal.decimal(s["delivery_charge"]),
        discount: Decimal.new(0), tax: Fiscal.indicator(code, "1"), service: "2"}]
    else
      lines
    end
  end

  defp present(value) when is_binary(value), do: if(String.trim(value) == "", do: nil, else: String.trim(value))
  defp present(_), do: nil
  defp money(value), do: value |> Decimal.round(2) |> Decimal.to_string(:normal)
  defp date(value), do: value |> Date.from_iso8601!() |> Calendar.strftime("%d-%m-%Y")
end
