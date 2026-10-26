defmodule TigooServer.Fe.PrintedInvoice.CLI do
  @moduledoc "CLI for offline PDFs from accepted CerteCF batches."
  def main(args) do
    {flags, rest, invalid} = OptionParser.parse(args, strict: [batch: :string, output: :string,
      journal: :string, chrome_path: :string, qr_version: :string, logo: :string, help: :boolean])
    if rest != [] or invalid != [], do: raise(ArgumentError, "Unknown arguments: #{inspect(rest ++ invalid)}")
    if flags[:help] do
      IO.puts("Generate receipt PDFs offline: --batch DIR [--output DIR] [--journal JSON] [--logo PNG_OR_JPEG] [--chrome-path EXECUTABLE] [--qr-version 8|auto]. Default batch: fe/data-test/generated/step4-attempt-6; default output: BATCH/printed. QR defaults to strict version 8; auto explicitly allows larger versions, whose DGII acceptance must be confirmed. Requires built Elixir modules including qqr, Chrome/Chromium, xmlsec1, xmllint and trust certificates. QR generation runs entirely in Elixir.")
      0
    else
      unless Keyword.get(flags, :qr_version, "8") in ["8", "auto"], do: raise(ArgumentError, "--qr-version must be 8 or auto")
      root = System.get_env("TIGOO_FE_REPO_ROOT") || Path.expand("..")
      caller = System.get_env("TIGOO_FE_CALLER_DIR") || File.cwd!()
      opts = Keyword.merge([batch: Path.join(root, "fe/data-test/generated/step4-attempt-6"),
        trusted_certificates: [Path.join(root, "fe/digifirma-ca-raiz.crt")],
        intermediate_certificates: [Path.join(root, "fe/digifirma-ca-subordinada-1.crt")]], flags)
      opts = Enum.reduce([:batch, :output, :journal, :logo], opts, fn key, acc ->
        if acc[key], do: Keyword.put(acc, key, Path.expand(acc[key], caller)), else: acc
      end)
      opts = Enum.reduce([:chrome_path], opts, fn key, acc ->
        if acc[key] && String.contains?(acc[key], "/"), do: Keyword.put(acc, key, Path.expand(acc[key], caller)), else: acc
      end)
      result = TigooServer.Fe.PrintedInvoice.generate!(opts)
      versions = result.documents |> Enum.map(& &1.qr_version) |> Enum.uniq() |> Enum.sort()
      IO.puts("QR versions: #{Enum.join(versions, ", ")}")
      if Enum.any?(versions, &(&1 > 8)), do: IO.puts("Review required: --qr-version auto produced QR versions above the documented version 8; this does not establish DGII acceptance.")
      IO.puts("Generated #{length(result.documents)} individual PDFs and #{length(result.uploads)} portal PDFs offline.\nOutput: #{result.output}\nCombined upload size: #{result.upload_bytes} bytes (limit 10000000)")
      Enum.each(result.uploads, fn upload -> IO.puts("#{upload.category}: #{upload.pdf_file} (#{length(upload.encfs)} invoices; #{upload.bytes} bytes)") end)
      IO.puts("Review the PDFs and QR codes before manual upload. No DGII requests made.")
      0
    end
  rescue
    error in [ArgumentError, File.Error, TigooServer.Fe.Generation.Error] ->
      IO.puts(:stderr, Exception.message(error))
      2
  end
end
