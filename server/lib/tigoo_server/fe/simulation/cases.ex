defmodule TigooServer.Fe.Simulation.Cases do
  @moduledoc "Builds the 25 portal cases from real sales, with explicit simulation provenance."
  alias TigooServer.Fe.Generation.Error
  @counts %{"31" => 4, "32" => 6, "33" => 1, "34" => 2, "41" => 2,
    "43" => 2, "44" => 2, "45" => 2, "46" => 2, "47" => 2}
  def counts, do: @counts

  def plan!(invoices) do
    fiscal = Enum.filter(invoices, &(String.starts_with?(&1.sequence, "B01") and Decimal.compare(&1.total, 0) == :gt))
    consumer = Enum.filter(invoices, &(String.starts_with?(&1.sequence, "B02") and Decimal.compare(&1.total, 0) == :gt and Decimal.compare(&1.total, 250_000) == :lt))
    if length(fiscal) < 4 or length(consumer) < 4, do: Error.fail!(:simulation, "Need at least four usable B01 and four low-amount B02 sales")
    highest = invoices |> Enum.filter(&(Decimal.compare(&1.total, 0) == :gt)) |> Enum.sort_by(& &1.total, {:desc, Decimal}) |> Enum.take(2)
    supplier = Enum.find(fiscal, &(String.length(&1.rnc) == 11)) || hd(fiscal)
    ordinary = Enum.with_index(Enum.take(fiscal, 4), 1) |> Enum.map(fn {sale, i} -> spec("31", i, sale, "Retail sale based on CSV") end)
    high = Enum.with_index(highest, 1) |> Enum.map(fn {sale, i} ->
      multiplier = Decimal.div(Decimal.new(250_000), sale.total) |> Decimal.round(0, :ceiling) |> Decimal.to_integer()
      spec("32", i, sale, "Simulated bulk quantity to meet >= DOP250000", max(multiplier, 1))
    end)
    low = Enum.with_index(Enum.take(consumer, 4), 3) |> Enum.map(fn {sale, i} -> spec("32", i, sale, "Low-amount consumption sale from CSV") end)
    notes = [
      Map.merge(spec("33", 1, hd(fiscal), "Simulated additional product charge"), %{reference: "31-1", selection: :first, modification: "3"}),
      Map.merge(spec("34", 1, Enum.at(fiscal, 1), "Simulated partial product return"), %{reference: "31-2", selection: :first, modification: "3"}),
      Map.merge(spec("34", 2, Enum.at(fiscal, 2), "Simulated full cancellation"), %{reference: "31-3", modification: "1"})
    ]
    purchases = for i <- 1..2, do: spec("41", i, supplier, "Simulated purchase; CSV customer assumed to be an unregistered supplier; VAT100% / ISR3% assumptions", i)
    expenses = for i <- 1..2, do: %{spec("43", i, Enum.at(consumer, i - 1), "Simulated minor cash expense using CSV goods") | selection: :first}
    special = for type <- ~w(44 45 46 47), i <- 1..2 do
      role = %{"44" => "special-regime buyer", "45" => "government buyer", "46" => "export buyer", "47" => "nonresident commercial advisory service concerning the source product; source net amount/quantity adapted as service fees/units; ISR27% assumption"}[type]
      %{spec(type, i, Enum.at(fiscal, rem(i + String.to_integer(type), length(fiscal))), "CSV customer/product adapted to a simulated #{role}; not evidence of actual status") | selection: :first}
    end
    plan = ordinary ++ high ++ low ++ notes ++ purchases ++ expenses ++ special
    if Enum.frequencies_by(plan, & &1.type) != @counts, do: Error.fail!(:simulation, "Scenario quota mismatch")
    plan
  end

  defp spec(type, index, sale, assumption, multiplier \\ 1) do
    %{id: "#{type}-#{index}", type: type, sale: sale, assumption: assumption,
      multiplier: multiplier, selection: :all, reference: nil, modification: nil,
      small_consumption: type == "32" and index >= 3}
  end

  def rows!(plan, ranges, opts) do
    {assigned, _} = Enum.map_reduce(plan, %{}, fn item, used ->
      index = Map.get(used, item.type, 0)
      sequence = ranges[item.type] |> Enum.fetch!(index) |> Integer.to_string() |> String.pad_leading(10, "0")
      {Map.put(item, :encf, "E" <> item.type <> sequence), Map.put(used, item.type, index + 1)}
    end)
    lookup = Map.new(assigned, &{&1.id, &1})
    overrides = Keyword.get(opts, :case_overrides, %{})
    unless is_map(overrides) and Enum.all?(overrides, fn {key, value} -> is_binary(key) and is_map(value) end), do: Error.fail!(:simulation, "Case overrides must map case IDs to field objects")
    unknown = Map.keys(overrides) -- Map.keys(lookup)
    if unknown != [], do: Error.fail!(:simulation, "Unknown override case IDs: #{Enum.join(unknown, ", ")}")
    assigned |> Enum.with_index(1) |> Enum.map(fn {item, index} ->
      fields = fields!(item, lookup, opts)
      fields = Enum.reduce(Map.get(overrides, item.id, %{}), fields, fn {key, value}, acc ->
        if key in ~w(ENCF TipoeCF RNCEmisor CasoPrueba FechaHoraFirma), do: Error.fail!(:simulation, "Cannot override reserved identity field #{key}")
        unless is_nil(value) or is_binary(value), do: Error.fail!(:simulation, "Override values must be strings or null")
        if is_nil(value), do: Map.delete(acc, key), else: Map.put(acc, key, value)
      end)
      small = item.type == "32" and Decimal.compare(Decimal.new(fields["MontoTotal"]), 250_000) == :lt
      if item.type == "32" and small != item.small_consumption, do: Error.fail!(:simulation, "Type-32 threshold case changed unexpectedly")
      cells = Map.new(fields, fn {key, value} -> {key, %{value: value, coordinate: "#{item.id}:#{key}"}} end)
      %{number: index, fields: fields, cells: cells, source_provenance: %{
        case_id: item.id, source_sequence: item.sale.sequence, original_sale_date: item.sale.date,
        original_billed_total: money(item.sale.total), quantity_multiplier: item.multiplier,
        source_csv_records: Enum.map(selected(item), & &1.record),
        original_rows: Enum.map(selected(item), &Map.take(&1, ~w(sequence product customer customer_document_id sale_date unit_price quantity price discount billed_to_customer))),
        assumptions: item.assumption, overrides: Map.get(overrides, item.id, %{})}}
    end)
  end

  defp selected(%{selection: :first, sale: sale}), do: Enum.take(sale.items, 1)
  defp selected(item), do: item.sale.items

  defp fields!(item, lookup, opts) do
    type = item.type
    date = Keyword.fetch!(opts, :date) |> Calendar.strftime("%d-%m-%Y")
    taxable = type in ~w(31 32 33 34 41 45)
    indicator = cond do taxable -> "1"; type == "46" -> "3"; true -> "4" end
    fields = %{"Version" => "1.0", "TipoeCF" => type, "ENCF" => item.encf,
      "RNCEmisor" => opts[:issuer_rnc], "RazonSocialEmisor" => opts[:issuer_name],
      "DireccionEmisor" => opts[:issuer_address], "FechaEmision" => date, "TipoPago" => "1"}
    fields = if type not in ~w(32 34), do: Map.put(fields, "FechaVencimientoSecuencia", opts[:sequence_expiry]), else: fields
    fields = if type in ~w(31 32 33 34 44 45 46), do: Map.put(fields, "TipoIngresos", "01"), else: fields
    fields = if taxable, do: Map.put(fields, "IndicadorMontoGravado", "1"), else: fields
    fields = cond do
      type == "43" -> fields
      type in ~w(46 47) -> Map.merge(fields, %{"IdentificadorExtranjero" => "SIM-EXT-#{item.id}", "RazonSocialComprador" => item.sale.customer})
      true -> Map.merge(fields, %{"RNCComprador" => item.sale.rnc, "RazonSocialComprador" => item.sale.customer})
    end
    fields = if type == "46", do: Map.put(fields, "PaisDestino", "ESTADOS UNIDOS"), else: fields
    lines = selected(item) |> Enum.map(fn source ->
      n = source.numbers
      %{name: String.trim(source["product"]), quantity: Decimal.mult(n["quantity"], item.multiplier),
        price: n["unit_price"], discount: Decimal.mult(n["discount"], item.multiplier),
        net: Decimal.mult(n["billed_to_customer"], item.multiplier)}
    end)
    total = sum(Enum.map(lines, & &1.net))
    base = if taxable, do: Decimal.div(total, Decimal.new("1.18")) |> Decimal.round(2), else: total
    vat = if taxable, do: Decimal.sub(total, base), else: Decimal.new(0)
    fields = Map.put(fields, "MontoTotal", money(total))
    fields = cond do
      taxable -> Map.merge(fields, %{"MontoGravadoTotal" => money(base), "MontoGravadoI1" => money(base),
        "ITBIS1" => "18", "TotalITBIS" => money(vat), "TotalITBIS1" => money(vat)})
      type == "46" -> Map.merge(fields, %{"MontoGravadoTotal" => money(total), "MontoGravadoI3" => money(total),
        "ITBIS3" => "0", "TotalITBIS" => "0.00", "TotalITBIS3" => "0.00"})
      true -> Map.put(fields, "MontoExento", money(total))
    end
    {fields, _, isr} = lines |> Enum.with_index(1) |> Enum.reduce({fields, Decimal.new(0), Decimal.new(0)}, fn {line, index}, {fields, retained, isr} ->
      suffix = "[#{index}]"
      simple = type in ~w(43 47)
      price = if simple, do: Decimal.div(line.net, line.quantity) |> Decimal.round(4), else: line.price
      if simple and not Decimal.equal?(Decimal.round(Decimal.mult(price, line.quantity), 2), line.net), do: Error.fail!(:simulation, "Net unit price cannot preserve source amount")
      values = %{"NumeroLinea" => Integer.to_string(index), "NombreItem" => if(type == "47", do: "SERVICIO DE ASESORIA COMERCIAL", else: line.name), "IndicadorFacturacion" => indicator,
        "IndicadorBienoServicio" => if(type == "47", do: "2", else: "1"), "CantidadItem" => money(line.quantity),
        "PrecioUnitarioItem" => Decimal.to_string(Decimal.round(price, 4), :normal), "MontoItem" => money(line.net)}
      values = if type == "47", do: Map.put(values, "DescripcionItem", "Asesoria comercial simulada sobre " <> line.name), else: values
      values = cond do
        simple -> values
        Decimal.compare(line.discount, 0) == :gt -> Map.put(values, "DescuentoMonto", money(line.discount))
        Decimal.compare(line.discount, 0) == :lt -> Map.put(values, "RecargoMonto", money(Decimal.negate(line.discount)))
        true -> values
      end
      line_base = if taxable, do: Decimal.div(line.net, Decimal.new("1.18")) |> Decimal.round(2), else: line.net
      line_vat = if index == length(lines), do: Decimal.sub(vat, retained), else: Decimal.sub(line.net, line_base)
      line_isr = cond do
        type == "41" -> Decimal.mult(line_base, Decimal.new("0.03")) |> Decimal.round(2)
        type == "47" -> Decimal.mult(line.net, Decimal.new("0.27")) |> Decimal.round(2)
        true -> Decimal.new(0)
      end
      values = if type in ~w(41 47), do: Map.merge(values, %{"IndicadorAgenteRetencionoPercepcion" => "1", "MontoISRRetenido" => money(line_isr)}), else: values
      values = if type == "41", do: Map.put(values, "MontoITBISRetenido", money(line_vat)), else: values
      fields = Enum.reduce(values, fields, fn {key, value}, acc -> Map.put(acc, key <> suffix, value) end)
      fields = cond do
        simple or Decimal.equal?(line.discount, 0) -> fields
        Decimal.compare(line.discount, 0) == :gt ->
          fields |> Map.put("TipoSubDescuento" <> suffix <> "[1]", "$")
            |> Map.put("MontoSubDescuento" <> suffix <> "[1]", money(line.discount))
        true ->
          # The shared mapper resolves the amount element's casing against this type's XSD.
          fields |> Map.put("TipoSubRecargo" <> suffix <> "[1]", "$")
            |> Map.put("MontoSubRecargo" <> suffix <> "[1]", money(Decimal.negate(line.discount)))
      end
      {fields, Decimal.add(retained, line_vat), Decimal.add(isr, line_isr)}
    end)
    fields = if type in ~w(41 47), do: Map.put(fields, "TotalISRRetencion", money(isr)), else: fields
    fields = if type == "41", do: Map.put(fields, "TotalITBISRetenido", money(vat)), else: fields
    # DGII's ValorPagar excludes withholding deductions: total - advance + prior balance.
    # These scenarios have neither an advance nor a prior balance.
    fields = if type in ~w(41 47), do: Map.put(fields, "ValorPagar", money(total)), else: fields
    fields = if item.reference do
      target = Map.fetch!(lookup, item.reference)
      Map.merge(fields, %{"NCFModificado" => target.encf, "FechaNCFModificado" => date,
        "CodigoModificacion" => item.modification, "RazonModificacion" => item.assumption})
    else
      fields
    end
    if type == "34", do: Map.put(fields, "IndicadorNotaCredito", "0"), else: fields
  end

  def money(value), do: value |> Decimal.round(2) |> Decimal.to_string(:normal)
  defp sum(values), do: Enum.reduce(values, Decimal.new(0), &Decimal.add/2)
end
