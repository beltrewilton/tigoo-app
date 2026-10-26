defmodule TigooServer.Fe.Simulation.SalesCsv do
  @moduledoc "Reads the sales export with quoted commas/quotes/newlines and Decimal-only arithmetic."
  alias TigooServer.Fe.Generation.{Error, Rules}
  @headers ~w(sequence product customer customer_document_id sale_date unit_price quantity price discount billed_to_customer)

  def read!(path) do
    if File.stat!(path).size > 10_000_000, do: Error.fail!(:csv, "Sales CSV exceeds 10 MB")
    bytes = File.read!(path) |> String.trim_leading(<<239, 187, 191>>)
    unless String.valid?(bytes), do: Error.fail!(:csv, "Expected UTF-8 CSV")
    parsed = parse(bytes, :start, [], [], []) |> Enum.reverse()
    if parsed == [], do: Error.fail!(:csv, "Sales CSV is empty")
    [headers | data] = parsed
    if headers != @headers, do: Error.fail!(:csv, "Unexpected sales report columns")
    lines = data |> Enum.with_index(2) |> Enum.map(fn {values, index} ->
      if length(values) != length(@headers), do: Error.fail!(:csv, "Wrong column count", row: index)
      raw = Map.new(Enum.zip(@headers, values))
      numbers = Map.new(~w(unit_price quantity price discount billed_to_customer), &{&1, Rules.decimal!(raw[&1])})
      unless Decimal.compare(numbers["quantity"], 0) == :gt and Decimal.compare(numbers["unit_price"], 0) != :lt and
               Decimal.compare(numbers["billed_to_customer"], 0) != :lt do
        Error.fail!(:csv, "Invalid quantity/price/net amount", row: index)
      end
      unless Decimal.equal?(Decimal.mult(numbers["unit_price"], numbers["quantity"]), numbers["price"]) and
               Decimal.equal?(Decimal.sub(numbers["price"], numbers["discount"]), numbers["billed_to_customer"]) do
        Error.fail!(:csv, "Price, discount and billed amount disagree", row: index)
      end
      Map.merge(raw, %{record: index, numbers: numbers})
    end)
    invoices = lines |> Enum.group_by(& &1["sequence"]) |> Enum.map(fn {sequence, items} ->
      first = hd(items)
      Enum.each(items, fn item ->
        unless Enum.all?(~w(customer customer_document_id sale_date), &(item[&1] == first[&1])), do: Error.fail!(:csv, "Inconsistent invoice identity/date: #{sequence}")
      end)
      %{sequence: sequence, customer: String.trim(first["customer"]), rnc: String.trim(first["customer_document_id"]),
        date: first["sale_date"], items: items, first_record: first.record,
        total: Enum.reduce(items, Decimal.new(0), &Decimal.add(&1.numbers["billed_to_customer"], &2))}
    end) |> Enum.sort_by(& &1.first_record)
    {valid, excluded} = Enum.split_with(invoices, &Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, &1.rnc))
    %{invoices: valid, summary: %{line_items: length(lines), invoices: length(invoices),
      usable_invoices: length(valid), excluded_line_items: Enum.reduce(excluded, 0, &(length(&1.items) + &2)),
      excluded: Enum.map(excluded, &%{sequence: &1.sequence, customer_document_id: &1.rnc,
        reason: "Identifier is not 9 or 11 digits; no invented correction applied"}),
      negative_discount_lines: Enum.count(lines, &(Decimal.compare(&1.numbers["discount"], 0) == :lt))}}
  end

  defp parse(<<>>, :quoted, _, _, _), do: Error.fail!(:csv, "Unterminated quoted field")
  defp parse(<<>>, :start, [], [], rows), do: rows
  defp parse(<<>>, _mode, field, row, rows), do: [Enum.reverse([finish(field) | row]) | rows]
  defp parse(<<34, 34, rest::binary>>, :quoted, field, row, rows), do: parse(rest, :quoted, [34 | field], row, rows)
  defp parse(<<34, rest::binary>>, :start, [], row, rows), do: parse(rest, :quoted, [], row, rows)
  defp parse(<<34, rest::binary>>, :quoted, field, row, rows), do: parse(rest, :closed, field, row, rows)
  defp parse(<<44, rest::binary>>, mode, field, row, rows) when mode != :quoted,
    do: parse(rest, :start, [], [finish(field) | row], rows)
  defp parse(<<13, 10, rest::binary>>, mode, field, row, rows) when mode != :quoted,
    do: parse(rest, :start, [], [], [Enum.reverse([finish(field) | row]) | rows])
  defp parse(<<10, rest::binary>>, mode, field, row, rows) when mode != :quoted,
    do: parse(rest, :start, [], [], [Enum.reverse([finish(field) | row]) | rows])
  defp parse(<<_, _::binary>>, :closed, _, _, _), do: Error.fail!(:csv, "Unexpected text after closing quote")
  defp parse(<<34, _::binary>>, :plain, _, _, _), do: Error.fail!(:csv, "Quote inside an unquoted field")
  defp parse(<<byte, rest::binary>>, mode, field, row, rows),
    do: parse(rest, if(mode == :start, do: :plain, else: mode), [byte | field], row, rows)
  defp finish(bytes), do: bytes |> Enum.reverse() |> :erlang.list_to_binary()
end
