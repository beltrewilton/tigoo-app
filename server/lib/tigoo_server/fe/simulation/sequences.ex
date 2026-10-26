defmodule TigooServer.Fe.Simulation.Sequences do
  @moduledoc "Persistent CerteCF Step-4 reservations. Even failed generation consumes its reserved range."
  alias TigooServer.Fe.Generation.Error
  @limit 10_000_000

  @doc "Conservatively skips all issued local ECF numbers, including earlier certification stages."
  def observed_next!(directory, issuer) do
    Path.wildcard(Path.join(directory, "**/manifest.json"))
    |> Enum.reduce(%{}, fn path, floors ->
      manifest = path |> File.read!() |> Jason.decode!()
      if manifest["authorized_issuer_rnc"] == issuer and Map.get(manifest, "document_type", "ECF") == "ECF" do
        Enum.reduce(Map.fetch!(manifest, "documents"), floors, fn doc, acc ->
          case Regex.run(~r/\AE([0-9]{2})([0-9]{10})\z/, doc["encf"] || "") do
            [_, type, digits] -> Map.update(acc, type, String.to_integer(digits) + 1, &max(&1, String.to_integer(digits) + 1))
            _ -> Error.fail!(:sequence, "Invalid eNCF in prior manifest: #{path}")
          end
        end)
      else
        floors
      end
    end)
  end

  def reserve!(path, issuer, counts, start, attempt, observed_next \\ %{}) do
    unless is_integer(start) and start in 1..@limit, do: Error.fail!(:sequence, "Initial sequence must be between 1 and 10000000")
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    lock = path <> ".lock"
    case File.mkdir(lock) do
      :ok -> :ok
      _ -> Error.fail!(:sequence, "Sequence ledger is locked: #{lock}")
    end
    try do
      ledger = if File.exists?(path) do
        value = path |> File.read!() |> Jason.decode!()
        unless value["issuer_rnc"] == issuer and value["purpose"] == "dgii_step4_simulation" and value["initial_start"] == start do
          Error.fail!(:sequence, "Ledger belongs to another issuer/purpose/start; never reset it to reuse numbers")
        end
        value
      else
        %{"issuer_rnc" => issuer, "purpose" => "dgii_step4_simulation", "initial_start" => start,
          "next" => Map.new(counts, fn {type, _} -> {type, start} end), "reservations" => []}
      end
      ranges = Map.new(counts, fn {type, count} ->
        recorded = Map.fetch!(ledger["next"], type)
        unless is_integer(recorded), do: Error.fail!(:sequence, "Corrupt sequence ledger for type #{type}")
        first = max(recorded, Map.get(observed_next, type, start))
        unless is_integer(first) and first >= start and first + count - 1 <= @limit, do: Error.fail!(:sequence, "Sequence range exhausted or corrupt for type #{type}")
        {type, Enum.to_list(first..(first + count - 1))}
      end)
      next = Map.new(ranges, fn {type, values} -> {type, List.last(values) + 1} end)
      reservation = %{"attempt" => attempt, "reserved_at" => DateTime.to_iso8601(DateTime.utc_now()),
        "observed_next" => observed_next, "ranges" => ranges}
      updated = ledger |> Map.put("next", next) |> Map.update!("reservations", &(&1 ++ [reservation]))
      temporary = path <> ".tmp-" <> attempt
      try do
        File.write!(temporary, Jason.encode!(updated, pretty: true) <> "\n", [:exclusive])
        File.rename!(temporary, path)
      after
        File.rm(temporary)
      end
      ranges
    after
      File.rmdir(lock)
    end
  end
end
