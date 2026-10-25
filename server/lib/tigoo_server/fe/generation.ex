defmodule TigooServer.Fe.Generation do
  @moduledoc """
  Offline, reusable XLSX → signed ECF/RFCE certification batch generation.

  `generate/1` returns `{:ok, manifest}` or `{:error, %Error{}}`. `generate!/1`
  raises instead. Neither starts Phoenix/Repo nor makes HTTP requests. Output is
  published only after the entire batch passes schema, source-field, signature,
  certificate-chain and reference checks. Existing outputs are never overwritten.

  Required options: `:workbook`, `:output`, `:issuer_rnc`, `:p12_path`, and either
  `:password` or `:credentials_file`. Trust roots must be supplied through
  `:trusted_certificates` or the existing `:fe_authentication` configuration.
  """
  alias TigooServer.Fe.Generation.{Command, Document, Error, Rules, Schema, Workbook, Xml}
  alias TigooServer.Sign

  @spec generate(keyword()) :: {:ok, map()} | {:error, Error.t()}
  def generate(opts) do
    {:ok, generate!(opts)}
  rescue
    error in Error -> {:error, error}
    error in File.Error ->
      {:error, %Error{stage: :file, message: "File operation #{error.action} failed for #{error.path}: #{:file.format_error(error.reason)}"}}
    _error -> {:error, %Error{stage: :generation, message: "Generation failed unexpectedly; no completed batch was published"}}
  end

  @spec generate!(keyword()) :: map()
  def generate!(opts) do
    Enum.each([:crypto, :public_key], fn app ->
      case Application.ensure_all_started(app) do
        {:ok, _} -> :ok
        {:error, _} -> Error.fail!(:dependency, "Cannot start #{app}")
      end
    end)
    workbook = required_option!(opts, :workbook) |> Path.expand()
    output = required_option!(opts, :output) |> Path.expand()
    issuer = required_option!(opts, :issuer_rnc)
    if not Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, issuer), do: Error.fail!(:options, "Issuer RNC must have 9 or 11 digits")
    identity = required_option!(opts, :p12_path) |> Path.expand()
    if not File.regular?(identity), do: Error.fail!(:options, "Signing identity is unavailable")
    password = password!(opts)
    if exists?(output), do: Error.fail!(:output, "Output already exists: #{output}")
    opts = native_options(opts)
    Enum.each([:xmlsec_path, :openssl_path, :xmllint_path], fn key ->
      unless System.find_executable(opts[key]), do: Error.fail!(:dependency, "Executable unavailable: #{opts[key]}")
    end)
    roots = Keyword.fetch!(opts, :trusted_certificates)
    if roots == [], do: Error.fail!(:options, "Trusted CA certificates are required for signed batch generation")
    Enum.each(roots ++ opts[:intermediate_certificates] ++ opts[:crls], fn path ->
      unless File.regular?(path), do: Error.fail!(:options, "Certificate-chain file is unavailable: #{path}")
    end)
    source_hash = sha256(File.read!(workbook))
    signed_at = DateTime.utc_now() |> DateTime.truncate(:second)
    rows = Workbook.read!(workbook)
    checked = Enum.map(rows, &%{row: &1, info: Rules.check!(&1, issuer)})
    schemas = checked |> Enum.map(& &1.info.type) |> Enum.uniq() |> Map.new(&{&1, Schema.load!(&1, opts)})
    documents = Enum.map(checked, fn %{row: row, info: info} ->
      try do
        built = Document.build_ecf!(row, Map.fetch!(schemas, info.type), signed_at)
        Rules.check_document!(row, built.tree)
        observations = Rules.observations(built.tree)
        if opts[:strict_arithmetic] && observations != [], do: Error.fail!(:arithmetic, "Source arithmetic observations require review", row: row.number)
        %{row: row, info: info, observations: observations}
      rescue
        error in Error ->
          if error.row, do: reraise(error, __STACKTRACE__)
          raise %{error | row: row.number, message: error.message <> " row=#{row.number}"}
      end
    end)
    ids = Enum.map(documents, & &1.info.encf)
    if length(Enum.uniq(ids)) != length(ids), do: Error.fail!(:references, "Duplicate eNCF in workbook")
    order = Rules.dependency_order!(documents)
    rfce_schema = if Enum.any?(documents, & &1.info.small_consumption?), do: Schema.load!("RFCE", opts), else: nil

    File.mkdir_p!(Path.dirname(output))
    lock = output <> ".lock"
    case File.mkdir(lock) do
      :ok -> :ok
      {:error, _} -> Error.fail!(:output, "Cannot reserve output; another run may own #{lock}")
    end
    stage = output <> ".staging-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    try do
      if exists?(output), do: Error.fail!(:output, "Output appeared during preparation")
      File.mkdir!(stage)
      Enum.each(~w(ecf/recepcion ecf/consumo-menor-250000 rfce), &File.mkdir_p!(Path.join(stage, &1)))
      records = Enum.map(documents, &write_document!(&1, schemas, rfce_schema, stage, identity, password, opts))
      if records |> Enum.map(& &1.certificate_sha256) |> Enum.uniq() |> length() != 1 do
        Error.fail!(:verification, "Signing certificate changed during the batch")
      end
      if sha256(File.read!(workbook)) != source_hash, do: Error.fail!(:verification, "Workbook changed during generation")
      Enum.each(Map.values(schemas) ++ List.wrap(rfce_schema), fn schema ->
        if sha256(File.read!(schema.path)) != schema.sha256, do: Error.fail!(:verification, "Schema changed during generation")
      end)
      low = Enum.count(documents, & &1.info.small_consumption?)
      normal = records |> Enum.reject(& &1.small_consumption) |> MapSet.new(& &1.encf)
      manifest = %{
        source_workbook: workbook, source_sha256: source_hash, worksheet: "ECF",
        generated_at: DateTime.to_iso8601(signed_at), authorized_issuer_rnc: issuer,
        certificate_sha256: records |> hd() |> Map.fetch!(:certificate_sha256),
        counts: %{ecf: length(records), normal_reception: length(records) - low, low_consumption: low, rfce: low},
        dependency_order: order, normal_reception_order: Enum.filter(order, &MapSet.member?(normal, &1)),
        external_reference_encfs: documents |> Enum.map(& &1.info.reference) |> Enum.reject(&(is_nil(&1) or &1 in ids)) |> Enum.uniq(),
        dgii_submitted: false, dgii_acceptance: "not_evaluated", documents: records
      }
      File.write!(Path.join(stage, "manifest.json"), Jason.encode!(manifest, pretty: true) <> "\n", [:exclusive])
      write_reports!(stage, manifest)
      if exists?(output), do: Error.fail!(:output, "Refusing to overwrite an existing batch")
      File.rename!(stage, output)
      Map.put(manifest, :output, output)
    after
      File.rm_rf(stage)
      File.rmdir(lock)
    end
  end

  defp write_document!(document, schemas, rfce_schema, stage, identity, password, opts) do
    %{row: row, info: info} = document
    filename = info.issuer_rnc <> info.encf <> ".xml"
    directory = if info.small_consumption?, do: "ecf/consumo-menor-250000", else: "ecf/recepcion"
    relative = directory <> "/" <> filename
    schema = Map.fetch!(schemas, info.type)
    built = Document.build_ecf!(row, schema, DateTime.utc_now() |> DateTime.truncate(:second))
    signed = sign!(built.xml, identity, password, opts, row.number)
    root = Document.assert_source_preserved!(signed, built.mappings, row.number)
    signature = Xml.signature!(root)
    save_verified!(signed, Path.join(stage, relative), schema, opts)
    record = %{
      source_row: row.number, case: row.fields["CasoPrueba"], type: info.type, encf: info.encf,
      issuer_rnc: info.issuer_rnc, amount_dop: info.amount, small_consumption: info.small_consumption?,
      ecf_file: relative, ecf_sha256: sha256(signed), ecf_schema: schema.path, ecf_schema_sha256: schema.sha256,
      signature_timestamp: built.timestamp, certificate_sha256: signature.certificate_sha256,
      schema_valid: true, signature_valid: true, certificate_chain_valid: true, source_fields_preserved: true,
      source_field_count: length(built.mappings), field_mappings: Document.manifest_mappings(built.mappings),
      reference_encf: info.reference, source_arithmetic_observations: document.observations,
      delivery: if(info.small_consumption?, do: "rfce_then_full_ecf_portal_upload", else: "normal_ecf_reception")
    }
    record = if info.small_consumption? do
      summary = Document.build_rfce!(signed, rfce_schema)
      signed_summary = sign!(summary.xml, identity, password, opts, row.number)
      summary_root = Xml.parse!(signed_summary)
      summary_signature = Xml.signature!(summary_root)
      if summary_signature.certificate_sha256 != signature.certificate_sha256, do: Error.fail!(:verification, "ECF and RFCE signers differ", row: row.number)
      if Xml.value(summary_root, ~w(Encabezado CodigoSeguridadeCF)) != summary.security_code, do: Error.fail!(:verification, "RFCE security code changed", row: row.number)
      Enum.each(~w(MontoTotal MontoGravadoTotal TotalITBIS), fn field ->
        if Xml.value(summary_root, ["Encabezado", "Totales", field]) != Xml.value(root, ["Encabezado", "Totales", field]) do
          Error.fail!(:verification, "RFCE total differs from ECF", row: row.number, field: field)
        end
      end)
      rfce_relative = "rfce/" <> filename
      save_verified!(signed_summary, Path.join(stage, rfce_relative), rfce_schema, opts)
      Map.merge(record, %{rfce_file: rfce_relative, rfce_sha256: sha256(signed_summary),
        rfce_schema: rfce_schema.path, rfce_schema_sha256: rfce_schema.sha256,
        rfce_security_code: summary.security_code, rfce_schema_valid: true, rfce_signature_valid: true})
    else
      record
    end
    if callback = opts[:on_document], do: callback.(record)
    record
  rescue
    error in Error ->
      if error.row, do: reraise(error, __STACKTRACE__)
      raise %{error | row: document.row.number, message: error.message <> " row=#{document.row.number}"}
  end

  defp sign!(xml, identity, password, opts, row) do
    # Sign.sign/4 also verifies the resulting bytes with the pinned leaf certificate.
    case Sign.sign(xml, identity, password, Keyword.take(opts, [:xmlsec_path, :openssl_path])) do
      {:ok, signed} -> signed
      {:error, reason} -> Error.fail!(:signing, "Signing failed: #{reason}", row: row)
    end
  end

  defp save_verified!(xml, path, schema, opts) do
    File.write!(path, xml, [:exclusive])
    Schema.validate_file!(path, schema, opts)
    certificate_args = Enum.flat_map([
      {:trusted_certificates, "--trusted-pem"}, {:intermediate_certificates, "--untrusted-pem"}, {:crls, "--crl-pem"}
    ], fn {key, flag} -> Enum.flat_map(opts[key], &[flag, &1]) end)
    Command.run!(opts[:xmlsec_path], ["--verify", "--crypto", "openssl", "--crypto-config", Path.dirname(path),
      "--enabled-reference-uris", "empty", "--enabled-key-data", "x509"] ++ certificate_args ++ [path])
    if sha256(File.read!(path)) != sha256(xml), do: Error.fail!(:verification, "Signed bytes changed during export")
  end

  defp native_options(opts) do
    config = Application.get_env(:tigoo_server, :fe_authentication, [])
    Enum.reduce([xmlsec_path: "xmlsec1", openssl_path: "openssl", xmllint_path: "xmllint",
      trusted_certificates: [], intermediate_certificates: [], crls: []], opts, fn {key, default}, acc ->
      Keyword.put_new(acc, key, Keyword.get(config, key, default))
    end)
  end

  defp password!(opts) do
    password = case Keyword.fetch(opts, :password) do
      {:ok, password} -> password
      :error ->
        bytes = required_option!(opts, :credentials_file) |> File.read!()
        case Regex.scan(~r/^[\t ]*Password[\t ]*[:=][\t ]*([^\r\n]+)\r?$/mi, bytes, capture: :all_but_first) do
          [[value]] -> value |> String.trim() |> String.trim("\"") |> String.trim("'")
          _ -> Error.fail!(:credentials, "Expected exactly one Password field in credentials file")
        end
    end
    if not is_binary(password) or password == "" or String.contains?(password, ["\0", "\r", "\n"]), do: Error.fail!(:credentials, "Invalid signing password")
    password
  end

  defp required_option!(opts, key), do: Keyword.get(opts, key) || Error.fail!(:options, "Missing option #{key}")
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp exists?(path), do: match?({:ok, _}, File.lstat(path))

  defp write_reports!(stage, manifest) do
    checksums = Enum.flat_map(manifest.documents, fn record ->
      summaries = if Map.has_key?(record, :rfce_file), do: [{record.rfce_file, record.rfce_sha256}], else: []
      [{record.ecf_file, record.ecf_sha256}] ++ summaries
    end) |> Enum.sort() |> Enum.map_join("\n", fn {path, hash} -> "#{hash}  #{path}" end)
    File.write!(Path.join(stage, "SHA256SUMS"), checksums <> "\n", [:exclusive])
    keys = ~w(source_row type encf amount_dop ecf_file rfce_file reference_encf delivery)a
    header = Enum.map(keys, &Atom.to_string/1)
    lines = Enum.map(manifest.documents, fn record -> Enum.map(keys, &Map.get(record, &1, "")) end)
    csv = [header | lines] |> Enum.map_join("\n", fn cells ->
      Enum.map_join(cells, ",", fn value -> "\"" <> String.replace(to_string(value), "\"", "\"\"") <> "\"" end)
    end)
    File.write!(Path.join(stage, "documents.csv"), csv <> "\n", [:exclusive])
    observations = Enum.reduce(manifest.documents, 0, &(length(&1.source_arithmetic_observations) + &2))
    File.write!(Path.join(stage, "README.md"), """
    # ECF certification batch

    Worksheet: ECF. Issuer RNC: #{manifest.authorized_issuer_rnc}.
    #{manifest.counts.ecf} signed ECFs; #{manifest.counts.rfce} signed RFCEs.

    - `ecf/recepcion`: #{manifest.counts.normal_reception} full documents for normal reception.
    - `rfce`: summaries for type 32 below DOP 250,000.00.
    - `ecf/consumo-menor-250000`: corresponding full ECFs for portal upload after RFCE acceptance.
    - `manifest.json`: schema/certificate fingerprints, field mappings, reference order and source observations.
    - `documents.csv`: document inventory. `SHA256SUMS`: exact signed XML checksums.

    Every XML passed XSD, source-field, signature and configured certificate-chain checks.
    Source arithmetic observations: #{observations}; review them in the manifest. Values were preserved.
    External reference eNCFs may need acceptance before notes in this batch; dependency order only
    resolves documents present in this workbook. Consult the referenced document when absent.
    Follow `normal_reception_order` and wait for required acceptance before dependent notes.
    No documents were submitted to DGII. DGII fiscal acceptance has not been evaluated.
    Do not edit or reformat signed bytes. Re-signing an ECF requires regenerating its RFCE.
    """, [:exclusive])
  end
end
