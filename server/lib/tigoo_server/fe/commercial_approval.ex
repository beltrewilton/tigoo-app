defmodule TigooServer.Fe.CommercialApproval do
  @moduledoc "Generates signed ACECF batches from the first ACEECF_Generadas worksheet."
  alias TigooServer.Fe.Credentials
  alias TigooServer.Fe.CommercialApproval.Document
  alias TigooServer.Fe.Generation.{Artifact, Error, Schema, Workbook, Xml}
  alias TigooServer.Sign
  @sheet "ACEECF_Generadas"

  @spec generate(keyword()) :: {:ok, map()} | {:error, Error.t()}
  def generate(opts) do
    {:ok, generate!(opts)}
  rescue
    error in Error -> {:error, error}
    error in [File.Error, ArgumentError] -> {:error, %Error{stage: :approval, message: Exception.message(error)}}
    _ -> {:error, %Error{stage: :approval, message: "Approval generation failed; no completed batch was published"}}
  end

  @spec generate!(keyword()) :: map()
  def generate!(opts) do
    {:ok, _} = Application.ensure_all_started(:public_key)
    workbook = required!(opts, :workbook) |> Path.expand()
    output = required!(opts, :output) |> Path.expand()
    buyer = required!(opts, :buyer_rnc)
    identity = required!(opts, :p12_path) |> Path.expand()
    unless File.regular?(identity), do: Error.fail!(:approval, "Signing identity is unavailable")
    password = Credentials.password!(opts)
    opts = Artifact.options(opts)
    Artifact.validate_options!(opts)
    if exists?(output), do: Error.fail!(:output, "Output already exists: #{output}")
    source_hash = workbook |> File.read!() |> Artifact.sha256()
    schema = Schema.load!("ACECF", opts)
    prepared = Workbook.read!(workbook, sheet: @sheet) |> Enum.map(fn row ->
      %{row: row, built: Document.build!(row, buyer, schema)}
    end)
    ids = Enum.map(prepared, & &1.built.info.encf)
    if length(Enum.uniq(ids)) != length(ids), do: Error.fail!(:approval, "Duplicate eNCF/upload filename; split conflicting issuers into separate batches")
    File.mkdir_p!(Path.dirname(output))
    lock = output <> ".lock"
    case File.mkdir(lock) do
      :ok -> :ok
      {:error, _} -> Error.fail!(:output, "Cannot reserve output: #{lock}")
    end
    stage = output <> ".staging-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    try do
      if exists?(output), do: Error.fail!(:output, "Output appeared during preparation")
      File.mkdir!(stage)
      File.mkdir!(Path.join(stage, "acecf"))
      records = Enum.map(prepared, &write_document!(&1, stage, schema, identity, password, opts))
      fingerprints = records |> Enum.map(& &1.certificate_sha256) |> Enum.uniq()
      if length(fingerprints) != 1, do: Error.fail!(:verification, "Signing certificate changed during generation")
      if Artifact.sha256(File.read!(workbook)) != source_hash or Artifact.sha256(File.read!(schema.path)) != schema.sha256 do
        Error.fail!(:verification, "Workbook or schema changed during generation")
      end
      manifest = %{document_type: "ACECF", worksheet: @sheet, source_workbook: workbook,
        source_sha256: source_hash, generated_at: DateTime.to_iso8601(DateTime.utc_now()),
        authorized_buyer_rnc: buyer, certificate_sha256: hd(fingerprints), count: length(records),
        dgii_submitted: false, dgii_acceptance: "not_evaluated", documents: records}
      File.write!(Path.join(stage, "manifest.json"), Jason.encode!(manifest, pretty: true) <> "\n", [:exclusive])
      checksums = Enum.map_join(records, "\n", &"#{&1.sha256}  #{&1.file}")
      File.write!(Path.join(stage, "SHA256SUMS"), checksums <> "\n", [:exclusive])
      write_inventory!(stage, records)
      File.write!(Path.join(stage, "README.md"), """
      # Signed commercial approvals (ACECF)

      #{length(records)} documents from #{@sheet}; authorized buyer #{buyer}.
      Files: `acecf/RNCComprador+eNCF.xml`. Invoice RNCEmisor values are preserved.
      Amounts are serialized with two decimals without changing their numeric value.
      Supplied FechaHoraAprobacionComercial and Estado values are preserved.
      Manifest includes row/cell mappings, raw and XML values, hashes, schema and signer.
      Every artifact passed schema, source-field, signature and configured CA-chain checks.
      No documents were sent to DGII. A document Estado of 2 is a commercial rejection;
      DGII receipt codigo 1 would mean that decision was successfully registered.
      Do not edit or reformat signed XMLs. Use the commercial-approval submission runner.
      """, [:exclusive])
      if exists?(output), do: Error.fail!(:output, "Refusing to overwrite an existing batch")
      File.rename!(stage, output)
      Map.put(manifest, :output, output)
    after
      File.rm_rf(stage)
      File.rmdir(lock)
    end
  end

  defp write_document!(%{row: row, built: built}, stage, schema, identity, password, opts) do
    signed = case Sign.sign(built.xml, identity, password, Keyword.take(opts, [:xmlsec_path, :openssl_path])) do
      {:ok, signed} -> signed
      {:error, reason} -> Error.fail!(:signing, "Approval signing failed: #{reason}", row: row.number)
    end
    root = Document.assert_source_preserved!(signed, built.mappings, row.number)
    signature = Xml.signature!(root)
    info = built.info
    relative = "acecf/" <> info.buyer_rnc <> info.encf <> ".xml"
    Artifact.save_verified!(signed, Path.join(stage, relative), schema, opts)
    record = Map.merge(info, %{file: relative, sha256: Artifact.sha256(signed), source_row: row.number,
      schema: schema.path, schema_sha256: schema.sha256, certificate_sha256: signature.certificate_sha256,
      schema_valid: true, signature_valid: true, certificate_chain_valid: true, source_field_count: length(built.mappings),
      field_mappings: Enum.map(built.mappings, &Map.delete(&1, :path))})
    if callback = opts[:on_document], do: callback.(record)
    record
  end

  @doc "Validates a generated ACECF manifest and returns jobs for the shared submission runner."
  def jobs!(batch, manifest, buyer, opts) do
    documents = manifest["documents"]
    unless manifest["worksheet"] == @sheet and manifest["authorized_buyer_rnc"] == buyer and is_list(documents) and documents != [] do
      Error.fail!(:approval, "Expected an ACECF manifest for the configured buyer")
    end
    ids = Enum.map(documents, & &1["encf"])
    if length(ids) != length(Enum.uniq(ids)), do: Error.fail!(:approval, "Duplicate eNCF in ACECF manifest")
    schema = Schema.load!("ACECF", opts)
    Enum.map(documents, fn record ->
      relative = record["file"]
      unless is_binary(relative), do: Error.fail!(:approval, "Missing approval file path")
      path = Path.expand(relative, batch)
      unless String.starts_with?(path, batch <> "/"), do: Error.fail!(:approval, "Approval file must stay inside batch")
      if File.stat!(path).size > 5_000_000, do: Error.fail!(:approval, "Approval exceeds 5 MB")
      bytes = File.read!(path)
      if Artifact.sha256(bytes) != record["sha256"], do: Error.fail!(:verification, "Approval checksum mismatch: #{relative}")
      root = Xml.parse!(bytes)
      info = Document.validate!(root, buyer)
      Enum.each(~w(issuer_rnc buyer_rnc encf amount_dop state approval_timestamp)a, fn key ->
        if Map.fetch!(info, key) != record[Atom.to_string(key)], do: Error.fail!(:approval, "Approval metadata differs from manifest: #{relative}")
      end)
      if Path.basename(path) != buyer <> info.encf <> ".xml", do: Error.fail!(:approval, "Invalid ACECF filename")
      if Xml.signature!(root).certificate_sha256 != manifest["certificate_sha256"], do: Error.fail!(:approval, "Approval signer differs from manifest")
      Schema.validate_file!(path, schema, opts)
      %{kind: :approval, encf: info.encf, reference: nil, file: relative, hash: record["sha256"], document_state: info.state}
    end)
  end

  defp write_inventory!(stage, records) do
    keys = ~w(source_row issuer_rnc buyer_rnc encf amount_dop state approval_timestamp file)a
    rows = [Enum.map(keys, &Atom.to_string/1) | Enum.map(records, fn record -> Enum.map(keys, &Map.fetch!(record, &1)) end)]
    csv = Enum.map_join(rows, "\n", fn values ->
      Enum.map_join(values, ",", fn value -> "\"" <> String.replace(to_string(value), "\"", "\"\"") <> "\"" end)
    end)
    File.write!(Path.join(stage, "documents.csv"), csv <> "\n", [:exclusive])
  end

  defp exists?(path), do: match?({:ok, _}, File.lstat(path))
  defp required!(opts, key), do: Keyword.get(opts, key) || Error.fail!(:options, "Missing option #{key}")
end
