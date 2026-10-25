defmodule TigooServer.Fe.Generation.Document do
  @moduledoc "Reusable ECF builders and RFCE derivation from finalized signed ECFs."
  alias TigooServer.Fe.Generation.{Error, Schema, Xml}

  @doc "Builds an unsigned ECF and an auditable, one-to-one source field mapping."
  def build_ecf!(row, schema, signed_at \\ DateTime.utc_now()) do
    fields = row.fields
    timestamp = signature_timestamp(signed_at)
    {assignments, mappings} = Enum.reduce(fields, {%{}, []}, fn
      {"CasoPrueba", _}, acc -> acc
      {"FechaHoraFirma", _}, _ -> Error.fail!(:mapping, "Signing time is generated, not imported", row: row.number)
      {header, value}, {assignments, mappings} ->
        {name, indices, section} = source_name(header)
        candidates = Enum.filter(schema.leaves, fn leaf ->
          leaf.name == name and length(leaf.repeats) == length(indices) and
            (is_nil(section) or section in leaf.path)
        end)
        # The input alias never determines XML casing; the chosen XSD does.
        candidates = if candidates == [] and name in ["MontosubRecargo", "MontoSubRecargo"] do
          Enum.filter(schema.leaves, fn leaf ->
            leaf.name in ["MontosubRecargo", "MontoSubRecargo"] and length(leaf.repeats) == length(indices)
          end)
        else
          candidates
        end
        leaf = case candidates do
          [leaf] -> leaf
          _ -> Error.fail!(:mapping, "No unique XSD target", row: row.number, field: header)
        end
        positions = Map.new(Enum.zip(leaf.repeats, indices))
        path = leaf.path |> Enum.with_index() |> Enum.map(fn {tag, depth} -> {tag, Map.get(positions, depth)} end)
        if Map.has_key?(assignments, path), do: Error.fail!(:mapping, "Duplicate XSD target", row: row.number, field: header)
        mapping = %{header: header, cell: row.cells[header].coordinate, path: path, value: value}
        {Map.put(assignments, path, value), [mapping | mappings]}
    end)
    assignments = Map.put(assignments, [{"ECF", nil}, {"FechaHoraFirma", nil}], timestamp)
    document = Schema.build!(schema, assignments)
    %{tree: document, xml: Xml.encode(document), mappings: Enum.reverse(mappings), timestamp: timestamp}
  end

  def signature_timestamp(%DateTime{} = time) do
    # DGII requires fixed GMT-4, not the host's local timezone.
    time |> DateTime.to_unix() |> Kernel.-(4 * 3600) |> DateTime.from_unix!()
    |> Calendar.strftime("%d-%m-%Y %H:%M:%S")
  end

  defp source_name(header) do
    indices = Regex.scan(~r/\[(\d+)\]/, header, capture: :all_but_first) |> List.flatten() |> Enum.map(&String.to_integer/1)
    name = String.replace(header, ~r/\[\d+\]/, "")
    case name do
      "ENCF" -> {"eNCF", indices, nil}
      "NumeroLinea" -> {name, indices, "DetallesItems"}
      "NumeroLineaDoR" -> {"NumeroLinea", indices, "DescuentosORecargos"}
      _ -> {name, indices, nil}
    end
  end

  @doc "Checks every imported field against the final signed bytes without re-encoding them."
  def assert_source_preserved!(signed_xml, mappings, row_number) do
    root = Xml.parse!(signed_xml)
    Enum.each(mappings, fn mapping ->
      value = root |> Xml.at(tl(mapping.path)) |> Xml.text()
      if value != mapping.value do
        Error.fail!(:verification, "Signed XML differs from source #{mapping.cell}", row: row_number, field: mapping.header)
      end
    end)
    root
  end

  @doc "Derives an unsigned RFCE using the full ECF signature's first six Base64 characters."
  def build_rfce!(signed_ecf, schema) do
    root = Xml.parse!(signed_ecf)
    if elem(root, 0) != "ECF" or Xml.value(root, ~w(Encabezado IdDoc TipoeCF)) != "32" do
      Error.fail!(:rfce, "RFCE requires a signed type-32 ECF")
    end
    total = root |> Xml.value(~w(Encabezado Totales MontoTotal)) |> Decimal.new()
    if Decimal.compare(total, Decimal.new("250000.00")) != :lt, do: Error.fail!(:rfce, "RFCE is only for totals below DOP 250000")
    signature = Xml.signature!(root)
    code = String.slice(signature.value, 0, 6)
    {name, attrs, children} = Xml.child(root, "Encabezado")
    source = Xml.node("RFCE", [{name, attrs, children ++ [Xml.leaf("CodigoSeguridadeCF", code)]}])
    summary = Schema.project!(schema, source)
    %{tree: summary, xml: Xml.encode(summary), security_code: code,
      ecf_certificate_sha256: signature.certificate_sha256}
  end

  def manifest_mappings(mappings) do
    Enum.map(mappings, fn mapping ->
      %{header: mapping.header, cell: mapping.cell, xml_path: Xml.path(mapping.path)}
    end)
  end
end
