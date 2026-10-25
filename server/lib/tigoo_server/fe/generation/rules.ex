defmodule TigooServer.Fe.Generation.Rules do
  @moduledoc """
  Generation-time business checks beyond XSD structure, with Decimal arithmetic.

  Certification values are authoritative. Arithmetic observations are reported,
  never silently repaired; `strict_arithmetic: true` makes observations fatal.
  XSD validation remains mandatory before a signed artifact is published.
  """
  alias TigooServer.Fe.Generation.{Error, Xml}
  @types ~w(31 32 33 34 41 43 44 45 46 47)

  def check!(row, issuer_rnc) do
    f = row.fields
    type = required!(row, "TipoeCF")
    encf = required!(row, "ENCF")
    issuer = required!(row, "RNCEmisor")
    if type not in @types, do: Error.fail!(:rules, "Unsupported type", row: row.number, field: "TipoeCF")
    if not Regex.match?(~r/\AE[0-9]{12}\z/, encf) or String.slice(encf, 1, 2) != type do
      Error.fail!(:rules, "eNCF and type disagree", row: row.number, field: "ENCF")
    end
    if issuer != issuer_rnc, do: Error.fail!(:rules, "Issuer differs from explicitly authorized RNC", row: row.number, field: "RNCEmisor")
    if f["CasoPrueba"] && f["CasoPrueba"] != issuer <> encf, do: Error.fail!(:rules, "Case identifier differs from RNC + eNCF", row: row.number)
    if required!(row, "Version") != "1.0", do: Error.fail!(:rules, "Expected Version 1.0", row: row.number)
    amount = required!(row, "MontoTotal") |> decimal!()
    if Decimal.compare(amount, 0) == :lt, do: Error.fail!(:rules, "Negative total", row: row.number)
    small = type == "32" and Decimal.compare(amount, "250000.00") == :lt
    if f["RNCComprador"] && f["IdentificadorExtranjero"], do: Error.fail!(:rules, "Buyer identifiers are mutually exclusive", row: row.number)
    if type == "32" and not small and is_nil(f["RNCComprador"] || f["IdentificadorExtranjero"]) do
      Error.fail!(:rules, "Buyer identification required at or above DOP 250000", row: row.number)
    end
    if type in ["33", "34"] do
      Enum.each(~w(NCFModificado FechaNCFModificado CodigoModificacion), &required!(row, &1))
    end
    Enum.each(f, fn {header, value} ->
      if String.starts_with?(header, "Fecha") do
        case Regex.run(~r/\A(\d{2})-(\d{2})-(\d{4})\z/, value, capture: :all_but_first) do
          [day, month, year] ->
            case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
              {:ok, _} -> :ok
              _ -> Error.fail!(:rules, "Invalid calendar date", row: row.number, field: header)
            end
          _ -> Error.fail!(:rules, "Expected dd-MM-yyyy date", row: row.number, field: header)
        end
      end
    end)
    %{type: type, encf: encf, issuer_rnc: issuer, amount: f["MontoTotal"],
      small_consumption?: small, reference: f["NCFModificado"]}
  end

  defp required!(row, field) do
    row.fields[field] || Error.fail!(:rules, "Required value is missing", row: row.number, field: field)
  end

  @doc "Checks conditional tax, withholding and foreign-currency fields from the PDF."
  def check_document!(row, tree) do
    items = tree |> Xml.child("DetallesItems") |> Xml.children("Item")
    indicators = items |> Enum.map(&Xml.value(&1, ["IndicadorFacturacion"])) |> Enum.uniq()
    Enum.each(indicators, fn
      rate when rate in ["1", "2", "3"] ->
        Enum.each(["MontoGravadoTotal", "MontoGravadoI#{rate}", "ITBIS#{rate}", "TotalITBIS", "TotalITBIS#{rate}"], &required!(row, &1))
      "4" -> required!(row, "MontoExento")
      "0" -> required!(row, "MontoNoFacturable")
      _ -> :ok # The matching XSD rejects unsupported indicators.
    end)
    Enum.each([{"MontoITBISRetenido", "TotalITBISRetenido"}, {"MontoISRRetenido", "TotalISRRetencion"}], fn {line_field, total_field} ->
      if Enum.any?(items, &(Xml.value(&1, ["Retencion", line_field]) != nil)), do: required!(row, total_field)
    end)
    if row.fields["TipoMoneda"] || Enum.any?(items, &Xml.child(&1, "OtraMonedaDetalle")) do
      Enum.each(~w(TipoMoneda TipoCambio MontoTotalOtraMoneda), &required!(row, &1))
      if Decimal.compare(decimal!(row.fields["TipoCambio"]), 0) != :gt do
        Error.fail!(:rules, "Exchange rate must be positive", row: row.number, field: "TipoCambio")
      end
    end
    :ok
  end

  def decimal!(value) do
    case Decimal.parse(value) do
      {%Decimal{coef: coefficient} = number, ""} when is_integer(coefficient) -> number
      _ -> Error.fail!(:rules, "Expected a finite decimal value")
    end
  end

  def observations(tree) do
    totals = Xml.child(Xml.child(tree, "Encabezado"), "Totales")
    value = fn name -> (Xml.value(totals, [name]) || "0") |> decimal!() end
    result = compare("MontoTotal", value.("MontoTotal"), sum(Enum.map(~w(MontoGravadoTotal MontoExento TotalITBIS MontoImpuestoAdicional), value)))
    result = result ++ compare_present(totals, "MontoGravadoTotal", ~w(MontoGravadoI1 MontoGravadoI2 MontoGravadoI3))
    result = result ++ compare_present(totals, "TotalITBIS", ~w(TotalITBIS1 TotalITBIS2 TotalITBIS3))
    header = Xml.child(tree, "Encabezado")
    payment_table = header |> Xml.child("IdDoc") |> Xml.child("TablaFormasPago")
    payments = if payment_table do
      payment_table |> Xml.children("FormaDePago") |> Enum.map(&(Xml.value(&1, ["MontoPago"]) |> decimal!()))
    else
      []
    end
    result = if payments == [], do: result, else: result ++ compare("sum(MontoPago) vs MontoTotal", sum(payments), value.("MontoTotal"))
    items = tree |> Xml.child("DetallesItems") |> Xml.children("Item")
    line_notes = Enum.flat_map(items, fn item ->
      quantity = Xml.value(item, ["CantidadItem"]) |> decimal!()
      price = Xml.value(item, ["PrecioUnitarioItem"]) |> decimal!()
      discount = (Xml.value(item, ["DescuentoMonto"]) || "0") |> decimal!()
      surcharge = (Xml.value(item, ["RecargoMonto"]) || "0") |> decimal!()
      expected = quantity |> Decimal.mult(price) |> Decimal.sub(discount) |> Decimal.add(surcharge) |> Decimal.round(2, :half_up)
      compare("MontoItem line #{Xml.value(item, ["NumeroLinea"])}", Xml.value(item, ["MontoItem"]) |> decimal!(), expected)
    end)
    result ++ line_notes
  end

  defp compare_present(totals, parent, components) do
    if Xml.child(totals, parent) && Enum.any?(components, &Xml.child(totals, &1)) do
      expected = components |> Enum.map(&((Xml.value(totals, [&1]) || "0") |> decimal!())) |> sum()
      compare(parent, Xml.value(totals, [parent]) |> decimal!(), expected)
    else
      []
    end
  end

  defp sum(values), do: Enum.reduce(values, Decimal.new(0), &Decimal.add/2)
  defp compare(rule, supplied, calculated) do
    if Decimal.equal?(supplied, calculated) do
      []
    else
      [%{rule: rule, supplied: Decimal.to_string(supplied, :normal),
        calculated: Decimal.to_string(calculated, :normal),
        difference: supplied |> Decimal.sub(calculated) |> Decimal.to_string(:normal),
        action: "preserved_source_values"}]
    end
  end

  @doc "Returns a stable topological order and flags references outside this workbook."
  def dependency_order!(documents) do
    lookup = Map.new(documents, &{&1.info.encf, &1})
    documents |> Enum.filter(&(&1.info.type == "34")) |> Enum.group_by(& &1.info.reference)
    |> Enum.each(fn {reference, notes} ->
      if original = lookup[reference] do
        total = notes |> Enum.map(&decimal!(&1.info.amount)) |> sum()
        if Decimal.compare(total, original.info.amount) == :gt do
          Error.fail!(:references, "Combined credit notes exceed #{reference}")
        end
      end
    end)
    {ordered, _} = Enum.reduce(documents, {[], MapSet.new()}, fn document, {ordered, done} ->
      visit!(document, lookup, ordered, done, MapSet.new())
    end)
    Enum.reverse(ordered)
  end

  defp visit!(document, lookup, ordered, done, active) do
    id = document.info.encf
    cond do
      MapSet.member?(done, id) -> {ordered, done}
      MapSet.member?(active, id) -> Error.fail!(:references, "Cyclic document reference", row: document.row.number)
      true ->
        reference = Map.get(lookup, document.info.reference)
        {ordered, done} = if reference do
          if reference.info.type == "32" and not reference.info.small_consumption? and
               is_nil(document.row.fields["RNCComprador"] || document.row.fields["IdentificadorExtranjero"]) do
            Error.fail!(:references, "Buyer identification required for a note affecting type 32 at or above DOP 250000", row: document.row.number)
          end
          if document.row.fields["FechaNCFModificado"] != reference.row.fields["FechaEmision"] do
            Error.fail!(:references, "Reference date differs from referenced document", row: document.row.number)
          end
          if document.info.type == "34" and Decimal.compare(document.info.amount, reference.info.amount) == :gt do
            Error.fail!(:references, "Credit note total exceeds referenced document", row: document.row.number)
          end
          visit!(reference, lookup, ordered, done, MapSet.put(active, id))
        else
          {ordered, done}
        end
        {[id | ordered], MapSet.put(done, id)}
    end
  end
end
