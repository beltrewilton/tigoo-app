defmodule TigooServer.Fe.Simulation.CLI do
  @moduledoc "Command line entry point for offline simulation generation and resumable CerteCF submission."
  alias TigooServer.Fe.{Simulation, Client, Submission}

  def main([mode | args]) when mode in ["generate", "submit"] do
    {flags, rest, invalid} = OptionParser.parse(args, strict: [csv: :string, output: :string,
      batch: :string, ledger: :string, history_directory: :string, sequence_start: :integer, issuer_rnc: :string,
      issuer_name: :string, issuer_address: :string, sequence_expiry: :string,
      case_overrides: :string, date: :string, p12_path: :string, credentials_file: :string,
      poll_attempts: :integer, poll_interval: :integer, help: :boolean])
    if rest != [] or invalid != [], do: raise(ArgumentError, "Unknown arguments: #{inspect(rest ++ invalid)}")
    if flags[:help] do
      IO.puts("#{mode}: --csv PATH --output DIR --ledger PATH --sequence-start 1 --issuer-address TEXT --case-overrides JSON --date YYYY-MM-DD; submit: --batch DIR --poll-attempts 20 --poll-interval 1000")
      0
    else
      root = System.get_env("TIGOO_FE_REPO_ROOT") || Path.expand("..")
      caller = System.get_env("TIGOO_FE_CALLER_DIR") || File.cwd!()
      defaults = [csv: Path.join(root, "fe/data-test/evofitdb-real-data-1792968037699.csv"),
        output: Path.join(root, "fe/data-test/generated/step4"),
        ledger: Path.join(root, "fe/data-test/simulation-sequences-131362702.json"),
        history_directory: Path.join(root, "fe/data-test/generated"),
        issuer_rnc: "131362702", p12_path: Path.join(root, "p12_companies/ans/22813977_identity.p12"),
        credentials_file: Path.join(root, "p12_companies/ans/credentials.txt"),
        trusted_certificates: [Path.join(root, "fe/digifirma-ca-raiz.crt")],
        intermediate_certificates: [Path.join(root, "fe/digifirma-ca-subordinada-1.crt")]]
      opts = Keyword.merge(defaults, flags)
      opts = Enum.reduce([:csv, :output, :ledger, :history_directory, :batch, :p12_path, :credentials_file, :case_overrides], opts, fn key, acc ->
        if acc[key], do: Keyword.put(acc, key, Path.expand(acc[key], caller)), else: acc
      end)
      if mode == "generate" do
        opts = if opts[:date], do: Keyword.put(opts, :date, Date.from_iso8601!(opts[:date])), else: opts
        opts = if opts[:case_overrides], do: Keyword.put(opts, :case_overrides, opts[:case_overrides] |> File.read!() |> Jason.decode!()), else: opts
        manifest = Simulation.generate!(opts)
        IO.puts("Generated #{manifest.counts.ecf} signed ECFs and #{manifest.counts.rfce} RFCEs. No HTTP requests made.\nBatch: #{manifest.output}\nSequence ledger: #{opts[:ledger]}")
        0
      else
        batch = opts[:batch] || opts[:output]
        IO.puts("DGII Step-4 environment: certecf; issuer RNC: #{opts[:issuer_rnc]}")
        client = Client.new(Keyword.put(opts, :environment, "certecf"))
        case Submission.run(batch, client, Keyword.merge(opts, expected_document_type: "ECF", expected_purpose: "dgii_step4_simulation")) do
          {:ok, report} -> IO.puts("Submission complete. Journal: #{report["report_path"]}"); 0
          {:error, error, report} ->
            IO.puts(:stderr, Exception.message(error))
            if report, do: IO.puts(:stderr, "Journal: #{report["report_path"]}")
            1
        end
      end
    end
  rescue
    error in [ArgumentError, File.Error, TigooServer.Fe.Generation.Error] -> IO.puts(:stderr, Exception.message(error)); 2
  end

  def main(_), do: (IO.puts(:stderr, "Expected generate or submit"); 2)
end
