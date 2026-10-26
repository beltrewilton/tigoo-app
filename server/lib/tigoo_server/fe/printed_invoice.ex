defmodule TigooServer.Fe.PrintedInvoice do
  @moduledoc "Offline receipt-style PDF representations of an accepted signed ECF batch."
  alias TigooServer.Fe.Generation.{Artifact, Command, Error, Schema, Xml}
  alias TigooServer.Fe.PrintedInvoice.Template

  @doc "Produces individual PDFs and category PDFs without modifying or re-signing source XML."
  def generate!(opts) do
    batch = Keyword.fetch!(opts, :batch) |> Path.expand()
    output = Keyword.get(opts, :output, Path.join(batch, "printed")) |> Path.expand()
    opts = Artifact.options(opts)
    Artifact.validate_options!(opts)
    chrome = opts[:chrome_path] || System.find_executable("google-chrome") ||
      System.find_executable("chromium") || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    Enum.each([chrome], fn executable ->
      unless System.find_executable(executable), do: Error.fail!(:dependency, "Executable unavailable: #{executable}")
    end)
    if File.exists?(output), do: Error.fail!(:output, "Refusing to overwrite printed output: #{output}")
    manifest_bytes = File.read!(Path.join(batch, "manifest.json"))
    manifest = Jason.decode!(manifest_bytes)
    journal_path = Keyword.get(opts, :journal, Path.join(batch, "submission-certecf.json"))
    journal_bytes = File.read!(journal_path)
    journal = Jason.decode!(journal_bytes)
    unless journal["status"] == "complete" and journal["environment"] == "certecf" and
        journal["manifest_sha256"] == Artifact.sha256(manifest_bytes) and
        journal["issuer_rnc"] == manifest["authorized_issuer_rnc"] and
        Map.get(manifest, "document_type", "ECF") == "ECF" do
      Error.fail!(:source, "Expected a completed CerteCF ECF submission journal matching this manifest")
    end
    documents = manifest["documents"]
    unless is_list(documents) and documents != [], do: Error.fail!(:source, "Empty ECF batch")
    logo = logo_data(opts[:logo])
    # Validate every source before invoking the renderer or publishing any output.
    sources = Enum.map(documents, fn doc ->
      source = source!(batch, doc, journal, opts)
      if Xml.signature!(source.root).certificate_sha256 != manifest["certificate_sha256"], do: Error.fail!(:source, "Signing certificate differs from batch manifest")
      source
    end)
    ids = Enum.map(sources, & &1.doc["encf"])
    if Enum.uniq(ids) != ids, do: Error.fail!(:source, "Duplicate eNCFs in batch")
    File.mkdir_p!(Path.dirname(output))
    lock = output <> ".lock"
    case File.mkdir(lock) do
      :ok -> :ok
      _ -> Error.fail!(:output, "Printed output is locked: #{lock}")
    end
    stage = output <> ".staging-" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    try do
      if File.exists?(output), do: Error.fail!(:output, "Output appeared during preparation")
      Enum.each(~w(individual upload html qr browser-profile), &File.mkdir_p!(Path.join(stage, &1)))
      rendered = Enum.map(sources, fn source ->
        name = source.doc["issuer_rnc"] <> source.doc["encf"]
        {url, code} = qr_payload!(source.root, source.doc)
        qr_file = "qr/#{name}.svg"
        qr = TigooServer.Fe.PrintedInvoice.Qr.render!(url, opts)
        svg = qr.svg
        File.write!(Path.join(stage, qr_file), svg, [:exclusive])
        content = Template.receipt(source.root, "data:image/svg+xml;base64," <> Base.encode64(svg), code, logo)
        html_file = "html/#{name}.html"
        pdf_file = "individual/#{name}.pdf"
        render!(stage, html_file, pdf_file, Template.page([content]), chrome)
        %{encf: source.doc["encf"], type: source.doc["type"], source_file: source.doc["ecf_file"],
          source_sha256: source.doc["ecf_sha256"], category: category(source.doc), content: content,
          html_file: html_file, pdf_file: pdf_file, pdf_sha256: hash_file(stage, pdf_file),
          qr_file: qr_file, qr_sha256: Artifact.sha256(svg), qr_url: url, qr_version: qr.version, security_code: code,
          acceptance_basis: if(source.doc["small_consumption"], do: "rfce_accepted_full_ecf_portal_status_not_in_journal", else: "ecf_accepted")}
      end)
      uploads = rendered |> Enum.group_by(& &1.category) |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {category, records} ->
          pdf = "upload/#{category}.pdf"
          render!(stage, "html/#{category}.html", pdf, Template.page(Enum.map(records, & &1.content)), chrome)
          %{category: category, pdf_file: pdf, pdf_sha256: hash_file(stage, pdf),
            bytes: File.stat!(Path.join(stage, pdf)).size, encfs: Enum.map(records, & &1.encf)}
        end)
      total = Enum.reduce(uploads, 0, &(&1.bytes + &2))
      if total > 10_000_000, do: Error.fail!(:output, "Portal PDFs total #{total} bytes; exceeds conservative 10 MB limit")
      if Artifact.sha256(File.read!(Path.join(batch, "manifest.json"))) != Artifact.sha256(manifest_bytes) or
          Artifact.sha256(File.read!(journal_path)) != Artifact.sha256(journal_bytes), do: Error.fail!(:source, "Source manifest/journal changed during rendering")
      Enum.each(sources, fn source ->
        if hash_file(batch, source.doc["ecf_file"]) != source.doc["ecf_sha256"], do: Error.fail!(:source, "Source XML changed during rendering")
      end)
      result = %{source_batch: batch, source_manifest_sha256: Artifact.sha256(manifest_bytes),
        source_journal_sha256: Artifact.sha256(journal_bytes), generated_at: DateTime.to_iso8601(DateTime.utc_now()),
        environment: "certecf", upload_bytes: total, uploads: uploads,
        documents: Enum.map(rendered, &Map.delete(&1, :content)),
        note: "Low-amount entries certify RFCE acceptance only; confirm full ECF portal acceptance separately. Category bundling follows the portal's one-file-per-category layout."}
      File.rm_rf!(Path.join(stage, "browser-profile"))
      File.write!(Path.join(stage, "manifest.json"), Jason.encode!(result, pretty: true) <> "\n", [:exclusive])
      files = Path.wildcard(Path.join(stage, "**/*")) |> Enum.filter(&File.regular?/1)
      checksums = Enum.map_join(files, "\n", fn path -> "#{Artifact.sha256(File.read!(path))}  #{Path.relative_to(path, stage)}" end)
      File.write!(Path.join(stage, "SHA256SUMS"), checksums <> "\n", [:exclusive])
      if File.exists?(output), do: Error.fail!(:output, "Refusing to overwrite printed output")
      File.rename!(stage, output)
      Map.put(result, :output, output)
    after
      File.rm_rf(stage)
      File.rmdir(lock)
    end
  end

  defp source!(batch, doc, journal, opts) do
    entry = journal["entries"][doc["encf"]]
    low = doc["small_consumption"] == true
    sent_file = if low, do: doc["rfce_file"], else: doc["ecf_file"]
    sent_hash = if low, do: doc["rfce_sha256"], else: doc["ecf_sha256"]
    expected_kind = if low, do: "rfce", else: "ecf"
    unless is_map(entry) and entry["state"] in ["accepted", "accepted_conditional"] and
        entry["file"] == sent_file and entry["sha256"] == sent_hash and
        entry["kind"] == expected_kind, do: Error.fail!(:source, "Missing matching acceptance for #{doc["encf"]}")
    path = safe_file!(batch, doc["ecf_file"])
    bytes = File.read!(path)
    if Artifact.sha256(bytes) != doc["ecf_sha256"], do: Error.fail!(:source, "Signed ECF checksum mismatch")
    root = Xml.parse!(bytes)
    unless elem(root, 0) == "ECF" and Xml.value(root, ~w(Encabezado IdDoc eNCF)) == doc["encf"] and
        Xml.value(root, ~w(Encabezado Emisor RNCEmisor)) == journal["issuer_rnc"] and
        Xml.value(root, ~w(Encabezado IdDoc TipoeCF)) == doc["type"] and
        Xml.value(root, ~w(Encabezado Totales MontoTotal)) == doc["amount_dop"], do: Error.fail!(:source, "Signed ECF identity differs from manifest")
    actual_low = doc["type"] == "32" and Decimal.compare(Decimal.new(doc["amount_dop"]), 250_000) == :lt
    if actual_low != low, do: Error.fail!(:source, "Incorrect consumption routing")
    Artifact.verify_file!(path, Schema.load!(doc["type"], opts), opts)
    if low do
      summary_path = safe_file!(batch, sent_file)
      summary_bytes = File.read!(summary_path)
      if Artifact.sha256(summary_bytes) != sent_hash, do: Error.fail!(:source, "RFCE checksum mismatch")
      Artifact.verify_file!(summary_path, Schema.load!("RFCE", opts), opts)
      summary = Xml.parse!(summary_bytes)
      code = String.slice(Xml.signature!(root).value, 0, 6)
      unless Xml.value(summary, ~w(Encabezado CodigoSeguridadeCF)) == code and
          Xml.value(summary, ~w(Encabezado IdDoc eNCF)) == doc["encf"] and
          Xml.value(summary, ~w(Encabezado Emisor RNCEmisor)) == doc["issuer_rnc"] and
          Xml.value(summary, ~w(Encabezado Totales MontoTotal)) == doc["amount_dop"] and
          Xml.signature!(summary).certificate_sha256 == Xml.signature!(root).certificate_sha256,
          do: Error.fail!(:source, "RFCE does not match signed full ECF")
    end
    %{root: root, doc: doc}
  end

  @doc "Builds the certification QR solely from final signed ECF values."
  def qr_payload!(root, doc) do
    code = String.slice(Xml.signature!(root).value, 0, 6)
    common = [{"rncemisor", Xml.value(root, ~w(Encabezado Emisor RNCEmisor))},
      {"encf", Xml.value(root, ~w(Encabezado IdDoc eNCF))},
      {"montototal", Xml.value(root, ~w(Encabezado Totales MontoTotal))}]
    {base, params} = if doc["small_consumption"] do
      {"https://fc.dgii.gov.do/certecf/consultatimbrefc", common}
    else
      {"https://ecf.dgii.gov.do/certecf/consultatimbre", common ++ [
        {"rnccomprador", Xml.value(root, ~w(Encabezado Comprador RNCComprador)) || ""},
        {"fechaemision", Xml.value(root, ~w(Encabezado Emisor FechaEmision))},
        {"fechafirma", Xml.value(root, ["FechaHoraFirma"])}]}
    end
    {base <> "?" <> URI.encode_query(params ++ [{"codigoseguridad", code}], :rfc3986), code}
  end

  defp safe_file!(batch, relative) when is_binary(relative) do
    path = Path.expand(relative, batch)
    unless String.starts_with?(path, batch <> "/") and File.regular?(path), do: Error.fail!(:source, "Invalid source file path")
    path
  end
  defp safe_file!(_, _), do: Error.fail!(:source, "Missing source file path")
  defp hash_file(directory, file), do: directory |> Path.join(file) |> File.read!() |> Artifact.sha256()
  defp category(%{"type" => "32", "small_consumption" => true}), do: "32-menor-250000"
  defp category(%{"type" => "32"}), do: "32-mayor-igual-250000"
  defp category(doc), do: doc["type"]

  defp render!(stage, html, pdf, content, chrome) do
    File.write!(Path.join(stage, html), content, [:exclusive])
    url = "file://" <> URI.encode(Path.join(stage, html))
    Command.run!(chrome, ["--headless", "--disable-gpu", "--disable-extensions", "--disable-background-networking",
      "--disable-sync", "--no-first-run", "--no-default-browser-check", "--no-pdf-header-footer",
      "--run-all-compositor-stages-before-draw", "--virtual-time-budget=2000",
      "--user-data-dir=" <> Path.join(stage, "browser-profile"),
      "--print-to-pdf=" <> Path.join(stage, pdf), url], 60_000)
    path = Path.join(stage, pdf)
    unless File.regular?(path) and File.stat!(path).size > 100 and
        File.open!(path, [:read, :binary], &IO.binread(&1, 5)) == "%PDF-", do: Error.fail!(:render, "Chrome did not produce a PDF: #{pdf}")
  end

  defp logo_data(nil), do: nil
  defp logo_data(path) do
    mime = case String.downcase(Path.extname(path)) do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      _ -> Error.fail!(:options, "Logo must be PNG or JPEG")
    end
    if File.stat!(path).size > 500_000, do: Error.fail!(:options, "Logo must be below 500 KB")
    "data:#{mime};base64," <> Base.encode64(File.read!(path))
  end
end
