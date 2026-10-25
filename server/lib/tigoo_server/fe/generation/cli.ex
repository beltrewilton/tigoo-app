defmodule TigooServer.Fe.Generation.CLI do
  @moduledoc "Command-line adapter for the reusable generation API."
  alias TigooServer.Fe.Generation

  def main(argv) do
    {arguments, rest, invalid} = OptionParser.parse(argv, strict: [
      workbook: :string, output: :string, issuer_rnc: :string, p12: :string,
      credentials: :string, schema_dir: :string, ca: [:string, :keep],
      intermediate: [:string, :keep], crl: [:string, :keep], strict_arithmetic: :boolean,
      xmlsec: :string, openssl: :string, xmllint: :string, help: :boolean
    ])
    cond do
      invalid != [] or rest != [] ->
        IO.puts(:stderr, "Unknown or invalid arguments. Use --help.")
        2
      arguments[:help] ->
        IO.puts(help())
        0
      true -> run(arguments)
    end
  end

  defp run(arguments) do
    caller = System.get_env("TIGOO_FE_CALLER_DIR") || File.cwd!()
    arguments = Enum.map(arguments, fn {key, value} ->
      cond do
        key in [:workbook, :output, :p12, :credentials, :schema_dir, :ca, :intermediate, :crl] ->
          {key, Path.expand(value, caller)}
        key in [:xmlsec, :openssl, :xmllint] and String.contains?(value, "/") ->
          {key, Path.expand(value, caller)}
        true -> {key, value}
      end
    end)
    root = System.get_env("TIGOO_FE_REPO_ROOT") || Path.expand("..", File.cwd!())
    workbook = Keyword.get(arguments, :workbook, Path.join(root, "fe/data-test/131362702-25102026004903.xlsx")) |> Path.expand()
    output = Keyword.get(arguments, :output, Path.join([root, "fe/data-test/generated", Path.basename(workbook, ".xlsx")])) |> Path.expand()
    opts = [
      workbook: workbook, output: output, issuer_rnc: Keyword.get(arguments, :issuer_rnc, "131362702"),
      p12_path: Keyword.get(arguments, :p12, Path.join(root, "p12_companies/ans/22813977_identity.p12")),
      credentials_file: Keyword.get(arguments, :credentials, Path.join(root, "p12_companies/ans/credentials.txt")),
      schema_directory: Keyword.get(arguments, :schema_dir, Application.app_dir(:tigoo_server, "priv/fe/xsd")),
      trusted_certificates: repeated_or_default(arguments, :ca, [Path.join(root, "fe/digifirma-ca-raiz.crt")]),
      intermediate_certificates: repeated_or_default(arguments, :intermediate, [Path.join(root, "fe/digifirma-ca-subordinada-1.crt")]),
      crls: Keyword.get_values(arguments, :crl), strict_arithmetic: Keyword.get(arguments, :strict_arithmetic, false),
      on_document: fn record ->
        suffix = if record.small_consumption, do: " + RFCE", else: ""
        IO.puts("Validated row #{record.source_row}: #{record.encf}#{suffix}")
      end
    ]
    opts = Enum.reduce([xmlsec: :xmlsec_path, openssl: :openssl_path, xmllint: :xmllint_path], opts, fn {flag, option}, acc ->
      case arguments[flag] do
        nil -> acc
        path -> Keyword.put(acc, option, path)
      end
    end)
    case Generation.generate(opts) do
      {:ok, manifest} ->
        IO.puts("Published #{manifest.counts.ecf} signed ECFs and #{manifest.counts.rfce} signed RFCEs.")
        IO.puts("Normal reception: #{manifest.counts.normal_reception}; low-amount full ECFs: #{manifest.counts.low_consumption}.")
        IO.puts("Output: #{manifest.output}")
        IO.puts("Reports: manifest.json, documents.csv, SHA256SUMS, README.md")
        observations = Enum.reduce(manifest.documents, 0, &(length(&1.source_arithmetic_observations) + &2))
        if observations > 0, do: IO.puts("Source arithmetic observations: #{observations}; review manifest.json. Supplied values were preserved.")
        IO.puts("No documents submitted to DGII.")
        0
      {:error, error} ->
        IO.puts(:stderr, Exception.message(error))
        1
    end
  end

  defp repeated_or_default(arguments, key, default) do
    case Keyword.get_values(arguments, key) do
      [] -> default
      values -> values
    end
  end

  defp help do
    """
    Usage: bash server/sh/generate_fe_certification.sh [options]

    --workbook PATH        XLSX whose first worksheet is ECF
    --output DIRECTORY     New output directory; never overwritten
    --issuer-rnc RNC       Explicit authorized issuer (default 131362702)
    --p12 PATH             Signing identity (default p12_companies/ans/22813977_identity.p12)
    --credentials PATH     File containing one Password field; never passed as an argument
    --schema-dir DIRECTORY Runtime XSD registry
    --ca PATH              Trusted PEM root, repeatable (default repo DigiFirma root)
    --intermediate PATH    Intermediate PEM, repeatable (default repo DigiFirma intermediate)
    --crl PATH             Optional PEM CRL, repeatable
    --strict-arithmetic    Refuse batches with arithmetic observations
    --xmlsec PATH          xmlsec1 executable override
    --openssl PATH         OpenSSL executable override
    --xmllint PATH         xmllint executable override
    --help

    Relative paths resolve from the caller's original working directory.
    The workbook test values are preserved, including zeroes and historical dates.
    This command performs offline generation only and does not submit to DGII.
    It requires previously built Elixir modules and never compiles the project.
    """
  end
end
