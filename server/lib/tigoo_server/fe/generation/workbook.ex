defmodule TigooServer.Fe.Generation.Workbook do
  @moduledoc """
  Reads a first worksheet using OTP ZIP and Saxy, without Excel or Python.
  The expected worksheet defaults to ECF; pass `sheet: name` for another format.

  Rows contain `:number`, `:fields` and `:cells`. Values are strings: no amount or
  identifier passes through a float. Only blank cells and the literal `#e` are
  omitted. Formulas and unsupported numeric date representations fail explicitly.
  """
  require Record
  Record.defrecordp(:zip_file, Record.extract(:zip_file, from_lib: "stdlib/include/zip.hrl"))
  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))
  alias TigooServer.Fe.Generation.{Error, Xml}
  @max_expanded 150_000_000

  @spec read!(Path.t(), keyword()) :: [map()]
  def read!(path, opts \\ []) do
    expected_sheet = Keyword.get(opts, :sheet, "ECF")
    if File.stat!(path).size > 20_000_000, do: Error.fail!(:workbook, "Workbook exceeds 20 MB")
    entries = unzip!(path)
    workbook = entry!(entries, "xl/workbook.xml") |> Xml.parse!()
    first = case workbook |> Xml.child("sheets") do
      nil -> Error.fail!(:workbook, "Missing worksheet list")
      sheets -> List.first(Xml.elements(sheets)) || Error.fail!(:workbook, "Missing worksheet list")
    end
    if Xml.attr(first, "name") != expected_sheet, do: Error.fail!(:workbook, "First worksheet must be #{expected_sheet}")

    relationships = entry!(entries, "xl/_rels/workbook.xml.rels") |> Xml.parse!() |> Xml.elements()
    {_, sheet_attributes, _} = first
    relationship_id = Enum.find_value(sheet_attributes, fn {name, value} -> if Xml.local(name) == "id", do: value end)
    relation = Enum.find(relationships, &(Xml.attr(&1, "Id") == relationship_id)) ||
      Error.fail!(:workbook, "Missing worksheet relationship for #{expected_sheet}")
    if Xml.attr(relation, "TargetMode") == "External", do: Error.fail!(:workbook, "External worksheets are unsupported")
    target = Xml.attr(relation, "Target")
    sheet_path = if String.starts_with?(target, "/"), do: String.trim_leading(target, "/"), else: Path.join("xl", target)
    strings = shared_strings(entries)
    styles = styles(entries)
    date1904 = case Xml.child(workbook, "workbookPr") do
      nil -> false
      properties -> Xml.attr(properties, "date1904") in ["1", "true"]
    end

    sheet = entry!(entries, sheet_path) |> Xml.parse!()
    sheet_rows = sheet |> Xml.child("sheetData") |> Xml.children("row")
    if sheet_rows == [], do: Error.fail!(:workbook, "#{expected_sheet} worksheet is empty")
    [header | body] = sheet_rows
    headers = Map.new(Xml.children(header, "c"), fn cell ->
      {column(cell), cell_value!(cell, strings, styles, date1904) |> String.trim()}
    end)

    names = Map.values(headers)
    if "" in names or length(Enum.uniq(names)) != length(names), do: Error.fail!(:workbook, "Blank or duplicate normalized header")

    rows = Enum.flat_map(body, fn row ->
      number = Xml.attr(row, "r") |> String.to_integer()
      cells = Enum.reduce(Xml.children(row, "c"), %{}, fn cell, acc ->
        value = cell_value!(cell, strings, styles, date1904)
        if value in ["", "#e"] do
          acc
        else
          name = Map.get(headers, column(cell)) || Error.fail!(:workbook, "Populated cell has no header", row: number, field: Xml.attr(cell, "r"))
          Map.put(acc, name, %{value: value, coordinate: Xml.attr(cell, "r")})
        end
      end)

      if map_size(cells) == 0, do: [], else: [%{
        number: number, cells: cells,
        fields: Map.new(cells, fn {name, cell} -> {name, cell.value} end)
      }]
    end)

    if rows == [], do: Error.fail!(:workbook, "No #{expected_sheet} data rows")
    rows
  end

  defp unzip!(path) do
    table = case :zip.table(String.to_charlist(path)) do
      {:ok, table} -> table
      {:error, _} -> Error.fail!(:workbook, "Cannot read XLSX ZIP directory")
    end

    files = Enum.filter(table, &Record.is_record(&1, :zip_file))
    expanded = Enum.reduce(files, 0, fn entry, total -> total + file_info(zip_file(entry, :info), :size) end)
    if expanded > @max_expanded or length(files) > 2000, do: Error.fail!(:workbook, "XLSX expansion limit exceeded")
    names = Enum.map(files, &(zip_file(&1, :name) |> List.to_string()))
    if length(Enum.uniq(names)) != length(names), do: Error.fail!(:workbook, "Duplicate ZIP members")

    case :zip.extract(String.to_charlist(path), [:memory]) do
      {:ok, entries} -> Map.new(entries, fn {name, bytes} -> {List.to_string(name), bytes} end)
      {:error, _} -> Error.fail!(:workbook, "Cannot extract XLSX in memory")
    end
  end

  defp entry!(entries, name), do: Map.get(entries, name) || Error.fail!(:workbook, "Missing XLSX member #{name}")
  defp column(cell), do: Xml.attr(cell, "r") |> String.replace(~r/\d+/, "")

  defp shared_strings(entries) do
    case Map.get(entries, "xl/sharedStrings.xml") do
      nil -> {}
      bytes -> bytes |> Xml.parse!() |> Xml.children("si") |> Enum.map(&rich_text/1) |> List.to_tuple()
    end
  end

  defp rich_text(node) do
    Enum.map_join(Xml.elements(node), fn child ->
      case Xml.local(elem(child, 0)) do
        "t" -> Xml.text(child)
        "r" -> child |> Xml.child("t") |> Xml.text() || ""
        _ -> ""
      end
    end)
  end

  defp styles(entries) do
    case Map.get(entries, "xl/styles.xml") do
      nil -> %{}
      bytes ->
        root = Xml.parse!(bytes)
        formats = case Xml.child(root, "numFmts") do
          nil -> %{}
          parent -> Map.new(Xml.children(parent, "numFmt"), &{Xml.attr(&1, "numFmtId"), Xml.attr(&1, "formatCode")})
        end
        case Xml.child(root, "cellXfs") do
          nil -> %{}
          parent -> parent |> Xml.children("xf") |> Enum.with_index() |> Map.new(fn {xf, index} ->
            id = Xml.attr(xf, "numFmtId", "0")
            {Integer.to_string(index), %{id: String.to_integer(id), format: Map.get(formats, id, "")}}
          end)
        end
    end
  end

  defp cell_value!(cell, strings, styles, date1904) do
    coordinate = Xml.attr(cell, "r")
    if Xml.child(cell, "f"), do: Error.fail!(:workbook, "Formula cells must be supplied as values", field: coordinate)
    raw = cell |> Xml.child("v") |> Xml.text() || ""
    case Xml.attr(cell, "t") do
      "s" ->
        case Integer.parse(raw) do
          {index, ""} when index >= 0 and index < tuple_size(strings) -> elem(strings, index)
          _ -> Error.fail!(:workbook, "Invalid shared-string index", field: coordinate)
        end
      "inlineStr" -> cell |> Xml.child("is") |> rich_text()
      "e" -> Error.fail!(:workbook, "Excel error cell", field: coordinate)
      "b" -> Error.fail!(:workbook, "Boolean cell is not an e-CF value", field: coordinate)
      "d" ->
        case Date.from_iso8601(raw) do
          {:ok, date} -> Calendar.strftime(date, "%d-%m-%Y")
          _ -> Error.fail!(:workbook, "Expected a date-only ISO cell", field: coordinate)
        end
      "str" -> raw
      _ -> numeric_value!(raw, Map.get(styles, Xml.attr(cell, "s")), date1904, coordinate)
    end
  end

  defp numeric_value!("", _, _, _), do: ""
  defp numeric_value!(raw, style, date1904, coordinate) do
    format = if style, do: style.format, else: ""
    date_style = style && (style.id in 14..22 or Regex.match?(~r/[dy]/i, String.replace(format, ~r/"[^"]*"|\[[^\]]*\]/, "")))
    cond do
      date_style ->
        value = Decimal.new(raw)
        if not Decimal.equal?(value, Decimal.round(value, 0)), do: Error.fail!(:workbook, "Date cell includes a time fraction", field: coordinate)
        serial = Decimal.to_integer(value)
        if not date1904 and serial == 60, do: Error.fail!(:workbook, "Excel's fictitious 1900-02-29 is invalid", field: coordinate)
        base = if date1904, do: ~D[1904-01-01], else: ~D[1899-12-31]
        days = if not date1904 and serial > 60, do: serial - 1, else: serial
        base |> Date.add(days) |> Calendar.strftime("%d-%m-%Y")
      Regex.match?(~r/\A0+\z/, format) and Regex.match?(~r/\A\d+\z/, raw) ->
        String.pad_leading(raw, String.length(format), "0")
      String.contains?(raw, ["e", "E"]) -> raw |> Decimal.new() |> Decimal.to_string(:normal)
      true -> raw
    end
  end
end
