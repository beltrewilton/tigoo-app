defmodule TigooServer.Fe.CommercialApproval.CLI do
  @moduledoc "Generation and submission command-line adapters for ACECF batches."
  alias TigooServer.Fe.{Client, CommercialApproval, Submission}

  def main(mode, argv) when mode in ["generate", "submit"] do
    {arguments, rest, invalid} = OptionParser.parse(argv, strict: [
      workbook: :string, output: :string, batch: :string, report: :string,
      buyer_rnc: :string, p12: :string, credentials: :string, environment: :string,
      schema_dir: :string, ca: [:string, :keep], intermediate: [:string, :keep],
      crl: [:string, :keep], xmlsec: :string, openssl: :string, xmllint: :string,
      receive_timeout: :integer, help: :boolean
    ])
    allowed = [:buyer_rnc, :p12, :credentials, :schema_dir, :xmlsec, :openssl, :xmllint, :help] ++
      if(mode == "generate", do: [:workbook, :output, :ca, :intermediate, :crl], else: [:batch, :report, :environment, :receive_timeout])
    cond do
      rest != [] or invalid != [] or Enum.any?(arguments, fn {key, _} -> key not in allowed end) ->
        IO.puts(:stderr, "Invalid #{mode} arguments. Use --help.")
        2
      arguments[:help] ->
        IO.puts(help(mode))
        0
      true -> run(mode, paths(arguments))
    end
  rescue
    error in [ArgumentError, File.Error, TigooServer.Fe.Generation.Error, TigooServer.Fe.Client.Error] ->
      IO.puts(:stderr, Exception.message(error))
      1
    _ ->
      IO.puts(:stderr, "ACECF command failed unexpectedly; inspect the output/journal before rerunning.")
      1
  end

  defp run(mode, arguments) do
    root = System.get_env("TIGOO_FE_REPO_ROOT") || Path.expand("..", File.cwd!())
    buyer = Keyword.get(arguments, :buyer_rnc, "131362702")
    shared = [p12_path: Keyword.get(arguments, :p12, Path.join(root, "p12_companies/ans/22813977_identity.p12")),
      credentials_file: Keyword.get(arguments, :credentials, Path.join(root, "p12_companies/ans/credentials.txt"))]
    shared = copy_options(arguments, shared, [xmlsec: :xmlsec_path, openssl: :openssl_path])
    if mode == "generate" do
      workbook = Keyword.get(arguments, :workbook, Path.join(root, "fe/131362702-25102026175246.xlsx"))
      output = Keyword.get(arguments, :output, Path.join([root, "fe/data-test/generated", Path.basename(workbook, ".xlsx")]))
      opts = shared ++ [workbook: workbook, output: output, buyer_rnc: buyer,
        trusted_certificates: repeated(arguments, :ca, [Path.join(root, "fe/digifirma-ca-raiz.crt")]),
        intermediate_certificates: repeated(arguments, :intermediate, [Path.join(root, "fe/digifirma-ca-subordinada-1.crt")]),
        crls: Keyword.get_values(arguments, :crl),
        on_document: fn record -> IO.puts("Validated ACECF row #{record.source_row}: #{record.encf}, Estado=#{record.state}") end]
      opts = copy_options(arguments, opts, [schema_dir: :schema_directory, xmllint: :xmllint_path])
      case CommercialApproval.generate(opts) do
        {:ok, manifest} ->
          IO.puts("Published #{manifest.count} signed ACECFs to #{manifest.output}")
          IO.puts("Reports: manifest.json, documents.csv, SHA256SUMS, README.md. No DGII requests made.")
          0
        {:error, error} ->
          IO.puts(:stderr, Exception.message(error))
          1
      end
    else
      batch = Keyword.get(arguments, :batch, Path.join(root, "fe/data-test/generated/131362702-25102026175246"))
      client = Client.new(shared ++ [issuer_rnc: buyer, environment: Keyword.get(arguments, :environment, "certecf"),
        receive_timeout: Keyword.get(arguments, :receive_timeout, 60_000)])
      opts = copy_options(arguments, [expected_document_type: "ACECF", on_result: fn encf, state, _ -> IO.puts("ACECF #{encf}: DGII #{state}") end],
        [report: :report, schema_dir: :schema_directory, xmllint: :xmllint_path])
      IO.puts("DGII AprobacionComercial environment: #{client.environment}; buyer RNC: #{buyer}")
      case Submission.run(batch, client, opts) do
        {:ok, report} ->
          IO.puts("DGII registered #{map_size(report["entries"])} commercial decisions. Journal: #{report["report_path"]}")
          0
        {:error, error, report} ->
          IO.puts(:stderr, Exception.message(error))
          if report, do: IO.puts(:stderr, "Journal: #{report["report_path"]}")
          1
      end
    end
  end

  defp paths(arguments) do
    caller = System.get_env("TIGOO_FE_CALLER_DIR") || File.cwd!()
    Enum.map(arguments, fn {key, value} ->
      cond do
        key in [:workbook, :output, :batch, :report, :p12, :credentials, :schema_dir, :ca, :intermediate, :crl] -> {key, Path.expand(value, caller)}
        key in [:xmlsec, :openssl, :xmllint] and String.contains?(value, "/") -> {key, Path.expand(value, caller)}
        true -> {key, value}
      end
    end)
  end

  defp copy_options(arguments, opts, mappings) do
    Enum.reduce(mappings, opts, fn {flag, key}, acc ->
      if value = arguments[flag], do: Keyword.put(acc, key, value), else: acc
    end)
  end

  defp repeated(arguments, key, default) do
    case Keyword.get_values(arguments, key) do
      [] -> default
      values -> values
    end
  end

  defp help(mode) do
    """
    ACECF #{mode}; first sheet ACEECF_Generadas. No compilation or formatting.

    Both commands: --buyer-rnc RNC --p12 PATH --credentials PATH --schema-dir PATH
                   --xmlsec PATH --openssl PATH --xmllint PATH --help
    Generation:    --workbook PATH --output NEW_DIRECTORY
                   --ca PATH --intermediate PATH --crl PATH (repeatable)
    Submission:    --batch DIRECTORY --report PATH --environment certecf|testecf|ecf
                   --receive-timeout MS

    Defaults use fe/131362702-25102026175246.xlsx, buyer 131362702 and the repo's
    p12_companies/ans identity. Output defaults to fe/data-test/generated/<workbook>.
    Submission defaults to that batch in certification; it performs real DGII POSTs.
    Relative paths resolve from your original working directory. Modules must
    already be built through the normal project workflow. No Phoenix/Repo startup.
    """
  end
end
