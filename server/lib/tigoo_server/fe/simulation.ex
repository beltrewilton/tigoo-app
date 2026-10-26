defmodule TigooServer.Fe.Simulation do
  @moduledoc "CSV-backed, explicitly documented CerteCF Step-4 simulation batches."
  alias TigooServer.Fe.Generation
  alias TigooServer.Fe.Generation.{Artifact, Document, Error, Rules, Schema}
  alias TigooServer.Fe.Simulation.{SalesCsv, Cases, Sequences}

  def generate!(opts) do
    source = Keyword.fetch!(opts, :csv) |> Path.expand()
    source_hash = Artifact.sha256(File.read!(source))
    sales = SalesCsv.read!(source)
    plan = Cases.plan!(sales.invoices)
    opts = opts |> Keyword.put_new(:issuer_rnc, "131362702")
      |> Keyword.put_new(:issuer_name, "EVOFIT WB SRL")
      |> Keyword.put_new(:issuer_address, "SANTO DOMINGO, REPUBLICA DOMINICANA")
      |> Keyword.put_new(:date, DateTime.utc_now() |> DateTime.add(-14_400) |> DateTime.to_date())
      |> Keyword.put_new(:sequence_expiry, "31-12-2028") |> Artifact.options()
    Artifact.validate_options!(opts)
    unless File.regular?(opts[:p12_path]), do: Error.fail!(:options, "Signing identity unavailable")
    TigooServer.Fe.Credentials.password!(opts)
    if File.exists?(Keyword.fetch!(opts, :output)), do: Error.fail!(:output, "Output already exists; choose a fresh attempt directory")
    # Reject malformed scenario configuration before consuming any real sequence.
    provisional = Map.new(Cases.counts(), fn {type, count} -> {type, Enum.to_list(1..count)} end)
    Enum.each(Cases.rows!(plan, provisional, opts), fn row ->
      info = Rules.check!(row, opts[:issuer_rnc])
      built = Document.build_ecf!(row, Schema.load!(info.type, opts))
      Rules.check_document!(row, built.tree)
      Rules.check_adjustments!(row, built.tree)
      Rules.check_simulation_payable!(row, built.tree)
      if Rules.observations(built.tree) != [], do: Error.fail!(:arithmetic, "Simulation arithmetic does not balance", row: row.number)
    end)
    attempt = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    history = Keyword.get(opts, :history_directory, Path.join(Path.dirname(Keyword.fetch!(opts, :ledger)), "generated"))
    unless File.dir?(history), do: Error.fail!(:sequence, "History directory unavailable: #{history}")
    observed_next = Sequences.observed_next!(history, opts[:issuer_rnc])
    ranges = Sequences.reserve!(Keyword.fetch!(opts, :ledger), opts[:issuer_rnc], Cases.counts(), Keyword.get(opts, :sequence_start, 1), attempt, observed_next)
    rows = Cases.rows!(plan, ranges, opts)
    Generation.generate_rows!(rows, Keyword.merge(opts,
      source_path: source, source_sha256: source_hash, source_kind: :csv,
      purpose: "dgii_step4_simulation", strict_arithmetic: true,
      source_metadata: %{sales: sales.summary, attempt: attempt, sequence_ranges: ranges,
        sequence_ledger: Path.expand(opts[:ledger]), history_directory: Path.expand(history), observed_next: observed_next,
        assumptions: ["User authorized documented quantity variations and invented scenarios using CSV products/customers",
          "18% inclusive VAT for taxable simulation cases; purchase ISR3%/VAT100%, foreign-payment ISR27% are scenario assumptions",
          "Customer identities reused in synthetic supplier/special-regime/government/export roles; actual eligibility is not established",
          "Issuer address is a configurable simulation placeholder; source dates and B-series numbers remain provenance only",
          "Current simulation issue date; initial lower bound 1; skip earlier local ECF batch numbers; remote-only submissions are not discoverable locally"],
        issuer_address: opts[:issuer_address]}))
  end
end
