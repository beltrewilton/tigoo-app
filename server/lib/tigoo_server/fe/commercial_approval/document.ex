defmodule TigooServer.Fe.CommercialApproval.Document do
  @moduledoc "ACECF construction and validation; the buyer is the approval's signing party."
  alias TigooServer.Fe.Generation.{Error, Rules, Schema, Xml}
  @detail "DetalleAprobacionComercial"

  @spec build!(map(), String.t(), map()) :: map()
  def build!(row, buyer_rnc, schema) do
    {assignments, mappings} = Enum.reduce(row.fields, {%{}, []}, fn {header, raw}, {assignments, mappings} ->
      leaf = case Enum.filter(schema.leaves, &(&1.name == header)) do
        [leaf] -> leaf
        _ -> Error.fail!(:approval, "Unknown or ambiguous ACECF column", row: row.number, field: header)
      end
      value = if header == "MontoTotal", do: amount!(raw), else: raw
      path = Enum.map(leaf.path, &{&1, nil})
      mapping = %{header: header, cell: row.cells[header].coordinate,
        xml_path: Xml.path(path), source_value: raw, xml_value: value, path: path}
      {Map.put(assignments, path, value), [mapping | mappings]}
    end)
    tree = Schema.build!(schema, assignments)
    info = validate!(tree, buyer_rnc)
    %{tree: tree, xml: Xml.encode(tree), info: info, mappings: Enum.reverse(mappings)}
  rescue
    error in Error ->
      if error.row, do: reraise(error, __STACKTRACE__)
      raise %{error | row: row.number, message: error.message <> " row=#{row.number}"}
  end

  @spec validate!(tuple(), String.t()) :: map()
  def validate!(root, buyer_rnc) do
    if elem(root, 0) != "ACECF", do: Error.fail!(:approval, "Expected ACECF root")
    detail = Xml.child(root, @detail) || Error.fail!(:approval, "Missing #{@detail}")
    fields = Map.new(Xml.elements(detail), fn {name, _, _} = child -> {name, Xml.text(child)} end)
    Enum.each(~w(Version RNCEmisor eNCF FechaEmision MontoTotal RNCComprador Estado FechaHoraAprobacionComercial), fn field ->
      unless is_binary(fields[field]) and fields[field] != "", do: Error.fail!(:approval, "Missing required value", field: field)
    end)
    if fields["Version"] != "1.0", do: Error.fail!(:approval, "Expected Version 1.0")
    Enum.each(~w(RNCEmisor RNCComprador), fn field ->
      unless Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, fields[field]), do: Error.fail!(:approval, "Invalid RNC", field: field)
    end)
    if fields["RNCComprador"] != buyer_rnc, do: Error.fail!(:approval, "Approval buyer differs from configured taxpayer RNC")
    unless String.length(fields["eNCF"]) in [9, 11, 13] and Regex.match?(~r/\A[A-Za-z0-9]+\z/, fields["eNCF"]), do: Error.fail!(:approval, "Invalid eNCF")
    unless fields["Estado"] in ["1", "2"], do: Error.fail!(:approval, "Estado must be 1 (accept) or 2 (reject)")
    reason = fields["DetalleMotivoRechazo"]
    if fields["Estado"] == "2" and (is_nil(reason) or String.trim(reason) == ""), do: Error.fail!(:approval, "Commercial rejection requires DetalleMotivoRechazo")
    if fields["MontoTotal"] != amount!(fields["MontoTotal"]), do: Error.fail!(:approval, "MontoTotal must have exactly two decimal places")
    emission = date!(fields["FechaEmision"])
    approved = datetime!(fields["FechaHoraAprobacionComercial"])
    if Date.compare(NaiveDateTime.to_date(approved), emission) == :lt, do: Error.fail!(:approval, "Approval predates invoice emission")
    %{issuer_rnc: fields["RNCEmisor"], buyer_rnc: fields["RNCComprador"], encf: fields["eNCF"],
      amount_dop: fields["MontoTotal"], state: fields["Estado"], approval_timestamp: fields["FechaHoraAprobacionComercial"]}
  end

  def assert_source_preserved!(signed, mappings, row_number) do
    root = Xml.parse!(signed)
    Enum.each(mappings, fn mapping ->
      if root |> Xml.at(tl(mapping.path)) |> Xml.text() != mapping.xml_value do
        Error.fail!(:verification, "Signed approval differs from source #{mapping.cell}", row: row_number, field: mapping.header)
      end
    end)
    root
  end

  defp amount!(raw) do
    number = Rules.decimal!(raw)
    rounded = Decimal.round(number, 2, :half_up)
    unless Decimal.compare(number, 0) != :lt and Decimal.equal?(number, rounded), do: Error.fail!(:approval, "MontoTotal must be nonnegative with no more than two decimal places")
    Decimal.to_string(rounded, :normal)
  end

  defp date!(value) do
    case Regex.run(~r/\A(\d{2})-(\d{2})-(\d{4})\z/, value, capture: :all_but_first) do
      [day, month, year] ->
        case Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day)) do
          {:ok, date} -> date
          _ -> Error.fail!(:approval, "Invalid FechaEmision")
        end
      _ -> Error.fail!(:approval, "FechaEmision must be dd-MM-yyyy")
    end
  end

  defp datetime!(value) do
    case Regex.run(~r/\A(\d{2})-(\d{2})-(\d{4}) (\d{2}:\d{2}:\d{2})\z/, value, capture: :all_but_first) do
      [day, month, year, time] ->
        case NaiveDateTime.from_iso8601("#{year}-#{month}-#{day}T#{time}") do
          {:ok, datetime} -> datetime
          _ -> Error.fail!(:approval, "Invalid FechaHoraAprobacionComercial")
        end
      _ -> Error.fail!(:approval, "FechaHoraAprobacionComercial must be dd-MM-yyyy HH:mm:ss")
    end
  end
end
