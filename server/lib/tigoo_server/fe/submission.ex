defmodule TigooServer.Fe.Submission do
  @moduledoc """
  Sequential sender for an ECF/RFCE or ACECF manifest, with a resumable JSON journal.

  Validates the batch before HTTP. ECF batches use dependency order, RFCE amount
  routing and result consultation; ACECF batches use direct approval responses.
  An interrupted/uncertain POST is never automatically repeated. A stored track
  ID is queried on resume; accepted entries are skipped. Tokens are never saved.
  """
  alias TigooServer.Fe.Client
  alias TigooServer.Fe.Client.Error
  alias TigooServer.Fe.Generation.{Rules, Schema, Xml}

  @spec run(Path.t(), Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t(), map() | nil}
  def run(directory, client, opts \\ []) do
    batch = Path.expand(directory)
    attempts = Keyword.get(opts, :poll_attempts, 20)
    interval = Keyword.get(opts, :poll_interval, 1000)
    unless is_integer(attempts) and attempts > 0 and is_integer(interval) and interval in 0..60_000 do
      fail!("Invalid poll_attempts or poll_interval")
    end
    manifest_bytes = File.read!(Path.join(batch, "manifest.json"))
    manifest = Jason.decode!(manifest_bytes)
    if opts[:expected_purpose] && manifest["purpose"] != opts[:expected_purpose] do
      fail!("Unexpected batch purpose; refusing submission")
    end
    if manifest["purpose"] == "dgii_step4_simulation" and client.environment != "certecf" do
      fail!("Step-4 simulation batches may only be submitted to CerteCF")
    end
    expected_type = opts[:expected_document_type]
    if expected_type && Map.get(manifest, "document_type", "ECF") != expected_type do
      fail!("Expected a #{expected_type} batch; refusing to use another reception service")
    end
    if manifest["purpose"] == "pos_ecf_test" and client.environment != "testecf" do
      fail!("POS test invoices may only be submitted to testecf")
    end
    jobs = preflight!(batch, manifest, client, opts)
    report_path = Keyword.get(opts, :report, Path.join(batch, "submission-#{client.environment}.json")) |> Path.expand()
    if report_path == Path.join(batch, "manifest.json"), do: fail!("Report must not replace the generation manifest")
    # A journal path must not collide with a signed artifact, even when explicitly supplied.
    artifacts = Enum.flat_map(manifest["documents"], fn doc -> [doc["ecf_file"], doc["rfce_file"], doc["file"]] end)
      |> Enum.reject(&is_nil/1) |> Enum.map(&Path.expand(&1, batch))
    if report_path in artifacts, do: fail!("Report must not replace a signed XML")
    File.mkdir_p!(Path.dirname(report_path))
    lock = report_path <> ".lock"
    case File.mkdir(lock) do
      :ok -> :ok
      {:error, _} -> fail!("Submission journal is locked: #{lock}")
    end
    try do
      report = load_report!(report_path, manifest, sha256(manifest_bytes), client)
      report = report |> Map.put("report_path", report_path) |> Map.put("status", "running") |> Map.delete("last_error")
      save!(report)
      complete? = Enum.all?(jobs, fn job ->
        entry = report["entries"][job.encf]
        entry && entry["state"] in ["accepted", "accepted_conditional"]
      end)
      authentication = if complete?, do: {:ok, client}, else: Client.authenticate(client)
      result = case authentication do
        {:ok, client} ->
          Enum.reduce_while(jobs, {:ok, report, client}, fn job, {:ok, report, session} ->
            case process(job, batch, session, report, attempts, interval, opts) do
              {:ok, report, session} -> {:cont, {:ok, report, session}}
              {:error, error, report} -> {:halt, {:error, error, report}}
            end
          end)
        {:error, error} -> {:error, error, report}
      end
      case result do
        {:ok, report, _session} ->
          report = Map.put(report, "status", "complete")
          save!(report)
          {:ok, report}
        {:error, error, report} ->
          report = report |> Map.put("status", "stopped") |> Map.put("last_error", error_data(error))
          save!(report)
          {:error, error, report}
      end
    after
      File.rmdir(lock)
    end
  rescue
    error in Error -> {:error, error, nil}
    error in TigooServer.Fe.Generation.Error ->
      {:error, %Error{operation: :preflight, message: Exception.message(error)}, nil}
    error in File.Error ->
      {:error, %Error{operation: :file, message: "Cannot #{error.action} #{error.path}: #{:file.format_error(error.reason)}"}, nil}
    _ -> {:error, %Error{operation: :submission, message: "Submission stopped unexpectedly; inspect the journal before retrying"}, nil}
  end

  defp preflight!(batch, %{"document_type" => "ACECF"} = manifest, client, opts) do
    TigooServer.Fe.CommercialApproval.jobs!(batch, manifest, client.issuer_rnc, opts)
  end

  defp preflight!(batch, manifest, client, opts) do
    documents = manifest["documents"]
    order = manifest["dependency_order"]
    source_supported = manifest["worksheet"] == "ECF" or
      (manifest["purpose"] == "dgii_step4_simulation" and manifest["source_format"] == "csv")
    unless source_supported and manifest["authorized_issuer_rnc"] == client.issuer_rnc and
             is_list(documents) and documents != [] and is_list(order) do
      fail!("Expected a Generation ECF manifest for the configured issuer")
    end
    lookup = Map.new(documents, &{&1["encf"], &1})
    if map_size(lookup) != length(documents) or Enum.sort(Map.keys(lookup)) != Enum.sort(order), do: fail!("Manifest has duplicate or missing eNCFs in dependency_order")
    fingerprint = manifest["certificate_sha256"]
    unless is_binary(fingerprint), do: fail!("Manifest has no signing certificate fingerprint")

    {jobs, _} = Enum.map_reduce(order, MapSet.new(), fn encf, seen ->
      doc = Map.fetch!(lookup, encf)
      if doc["issuer_rnc"] != client.issuer_rnc, do: fail!("Manifest contains a different issuer")
      reference = doc["reference_encf"]
      if Map.has_key?(lookup, reference) and not MapSet.member?(seen, reference), do: fail!("Manifest dependency order is invalid")
      root = validate_file!(batch, doc["ecf_file"], doc["ecf_sha256"], "ECF", doc, fingerprint, opts)
      if manifest["purpose"] == "dgii_step4_simulation" do
        Rules.check_adjustments!(%{number: doc["source_row"]}, root)
        Rules.check_simulation_payable!(%{number: doc["source_row"]}, root)
      end
      small = doc["type"] == "32" and Decimal.compare(Rules.decimal!(doc["amount_dop"]), "250000.00") == :lt
      if small != doc["small_consumption"], do: fail!("Manifest consumption routing disagrees with amount and type")
      job = if small do
        summary = validate_file!(batch, doc["rfce_file"], doc["rfce_sha256"], "RFCE", doc, fingerprint, opts)
        code = root |> Xml.signature!() |> Map.fetch!(:value) |> String.slice(0, 6)
        if Xml.value(summary, ~w(Encabezado CodigoSeguridadeCF)) != code, do: fail!("RFCE security code differs from full ECF")
        %{kind: :rfce, encf: encf, reference: reference, file: doc["rfce_file"], hash: doc["rfce_sha256"]}
      else
        %{kind: :ecf, encf: encf, reference: reference, file: doc["ecf_file"], hash: doc["ecf_sha256"]}
      end
      {job, MapSet.put(seen, encf)}
    end)
    jobs
  end

  defp validate_file!(batch, relative, expected, wanted_root, doc, fingerprint, opts) do
    unless is_binary(relative) and is_binary(expected), do: fail!("Manifest is missing a signed file or checksum")
    path = Path.expand(relative, batch)
    unless String.starts_with?(path, batch <> "/"), do: fail!("Signed XML path must stay inside the batch")
    if File.stat!(path).size > 5_000_000, do: fail!("Signed XML exceeds 5 MB")
    xml = File.read!(path)
    if sha256(xml) != expected, do: fail!("Signed XML checksum mismatch: #{relative}")
    root = Xml.parse!(xml)
    if wanted_root == "ECF", do: Rules.check_service_kind!(root, doc["source_row"])
    unless elem(root, 0) == wanted_root and Xml.value(root, ~w(Encabezado IdDoc eNCF)) == doc["encf"] and
             Xml.value(root, ~w(Encabezado IdDoc TipoeCF)) == doc["type"] and
             Xml.value(root, ~w(Encabezado Emisor RNCEmisor)) == doc["issuer_rnc"] and
             Xml.value(root, ~w(Encabezado Totales MontoTotal)) == doc["amount_dop"] do
      fail!("Signed document identity/total differs from manifest: #{relative}")
    end
    if Path.basename(path) != doc["issuer_rnc"] <> doc["encf"] <> ".xml", do: fail!("Invalid upload filename")
    if Xml.signature!(root).certificate_sha256 != fingerprint, do: fail!("Document signing certificate differs from manifest")
    schema = Schema.load!(if(wanted_root == "RFCE", do: "RFCE", else: doc["type"]), opts)
    Schema.validate_file!(path, schema, opts)
    root
  end

  defp load_report!(path, manifest, hash, client) do
    if File.exists?(path) do
      report = path |> File.read!() |> Jason.decode!()
      party = if manifest["document_type"] == "ACECF", do: report["buyer_rnc"], else: report["issuer_rnc"]
      unless report["manifest_sha256"] == hash and report["environment"] == client.environment and
               party == client.issuer_rnc and is_map(report["entries"]) do
        fail!("Existing journal belongs to another manifest, environment or taxpayer")
      end
      report
    else
      report = %{"version" => 1, "manifest_sha256" => hash, "environment" => client.environment,
        "issuer_rnc" => client.issuer_rnc, "created_at" => now(), "status" => "running", "entries" => %{},
        "portal_uploads" => manifest["documents"] |> Enum.filter(& &1["small_consumption"]) |> Enum.map(& &1["ecf_file"])}
      if manifest["document_type"] == "ACECF" do
        report |> Map.delete("issuer_rnc") |> Map.put("buyer_rnc", client.issuer_rnc) |> Map.put("document_type", "ACECF")
      else
        report
      end
    end
  end

  defp process(job, batch, client, report, attempts, interval, opts) do
    report = reconcile_recorded_approval!(job, client, report)
    entry = report["entries"][job.encf]
    reference = report["entries"][job.reference]
    cond do
      entry && entry["state"] in ["accepted", "accepted_conditional"] -> {:ok, report, client}
      reference && reference["state"] not in ["accepted", "accepted_conditional"] ->
        stopped(report, "Referenced document #{job.reference} is not accepted")
      entry && entry["state"] == "pending" && is_binary(entry["track_id"]) ->
        poll(job, client, report, attempts, interval, opts)
      entry && entry["state"] not in ["not_sent"] ->
        stopped(report, "#{job.encf} has state #{entry["state"]}; reconcile with DGII before another POST")
      true -> post(job, batch, client, report, attempts, interval, opts)
    end
  end

  # A previously unknown response can become recognizable after a classifier fix.
  # Reconcile only an actual stored receipt for the same hash-pinned upload; an
  # interrupted POST without a receipt must remain blocked.
  defp reconcile_recorded_approval!(%{kind: :approval} = job, client, report) do
    entry = report["entries"][job.encf]
    if is_map(entry) and entry["state"] == "unknown" and entry["kind"] == "approval" and
         entry["sha256"] == job.hash and entry["file"] == job.file and
         entry["document_state"] == job.document_state and is_map(entry["result"]) and
         response_matches?(entry["result"], job, client, nil) do
      case Client.status(entry["result"], :approval) do
        state when state in [:accepted, :rejected] ->
          merge_entry!(report, job.encf, %{"state" => Atom.to_string(state),
            "reclassified_from" => "unknown", "classification_source" => "recorded_dgii_response"})
        _ -> report
      end
    else
      report
    end
  end
  defp reconcile_recorded_approval!(_job, _client, report), do: report

  defp post(job, batch, client, report, attempts, interval, opts) do
    entry = %{"state" => "sending", "kind" => Atom.to_string(job.kind), "file" => job.file,
      "sha256" => job.hash, "started_at" => now()}
    entry = if job.kind == :approval, do: Map.put(entry, "document_state", job.document_state), else: entry
    report = update!(report, job.encf, entry)
    path = Path.expand(job.file, batch)
    response = case job.kind do
      :ecf -> Client.send_ecf(client, path, expected_sha256: job.hash)
      :rfce -> Client.send_rfce(client, path, expected_sha256: job.hash)
      :approval -> Client.send_approval(client, path, expected_sha256: job.hash)
    end
    case response do
      {:error, error} ->
        state = cond do
          error.operation in [:document, :seed, :authenticate] -> "not_sent"
          job.kind == :approval and error.http_status == 400 and is_map(error.details) ->
            if Client.status(error.details, :approval) == :rejected, do: "rejected", else: "unknown"
          true -> "unknown"
        end
        report = update!(report, job.encf, Map.merge(entry, %{"state" => state, "error" => error_data(error)}))
        {:error, error, report}
      {:ok, body, client} ->
        if job.kind == :ecf do
          track = body["trackId"]
          if is_binary(track) and String.trim(track) != "" do
            report = update!(report, job.encf, Map.merge(entry, %{"state" => "pending", "track_id" => track, "upload_response" => body}))
            poll(job, client, report, attempts, interval, opts)
          else
            report = update!(report, job.encf, Map.merge(entry, %{"state" => "unknown", "upload_response" => body}))
            stopped(report, "DGII returned no trackId for #{job.encf}; do not blindly repost")
          end
        else
          finish_response(job, body, client, report, opts)
        end
    end
  end

  defp poll(job, client, report, attempts, interval, opts) do
    track = report["entries"][job.encf]["track_id"]
    case Client.result(client, track) do
      {:ok, body, client} ->
        if not response_matches?(body, job, client, track) do
          report = merge_entry!(report, job.encf, %{"state" => "unknown", "result" => body})
          stopped(report, "Track query identity differs from #{job.encf}")
        else
          state = Client.status(body)
          if state in [:pending, :not_found] do
            report = merge_entry!(report, job.encf, %{"state" => "pending", "result" => body})
            poll_again(job, client, report, attempts, interval, opts)
          else
            finish_response(job, body, client, report, opts)
          end
        end
      {:error, %{http_status: 404} = error} ->
        report = merge_entry!(report, job.encf, %{"query_error" => error_data(error)})
        poll_again(job, client, report, attempts, interval, opts)
      {:error, error} ->
        report = merge_entry!(report, job.encf, %{"query_error" => error_data(error)})
        {:error, error, report}
    end
  end

  defp poll_again(job, client, report, attempts, interval, opts) do
    if attempts > 1 do
      Process.sleep(interval)
      poll(job, client, report, attempts - 1, interval, opts)
    else
      stopped(report, "#{job.encf} remains pending; rerun with the same journal to query its trackId without reposting")
    end
  end

  defp finish_response(job, body, client, report, opts) do
    state = if response_matches?(body, job, client, nil), do: Client.status(body, job.kind), else: :unknown
    state = if Client.accepted?(state) or state == :rejected, do: state, else: :unknown
    report = merge_entry!(report, job.encf, %{"state" => Atom.to_string(state), "result" => body})
    if callback = opts[:on_result], do: callback.(job.encf, state, body)
    if Client.accepted?(state), do: {:ok, report, client}, else: stopped(report, "DGII #{state} result for #{job.encf}; inspect the recorded response")
  end

  defp response_matches?(body, job, client, track) do
    encf = body["encf"] || body["eNCF"]
    (is_nil(encf) or encf == job.encf) and
      (is_nil(body["rnc"]) or body["rnc"] == client.issuer_rnc) and
      (is_nil(track) or is_nil(body["trackId"]) or body["trackId"] == track)
  end

  defp merge_entry!(report, encf, changes), do: update!(report, encf, Map.merge(report["entries"][encf], changes))
  defp update!(report, encf, entry) do
    report = put_in(report, ["entries", encf], Map.put(entry, "updated_at", now()))
    save!(report)
    report
  end

  defp save!(report) do
    path = report["report_path"]
    temporary = path <> ".tmp-" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
    try do
      File.write!(temporary, Jason.encode!(Map.put(report, "updated_at", now()), pretty: true) <> "\n", [:exclusive])
      File.rename!(temporary, path)
    after
      File.rm(temporary)
    end
  end

  defp error_data(error), do: %{"operation" => error.operation, "message" => error.message,
    "http_status" => error.http_status, "uncertain" => error.uncertain, "details" => error.details}
  defp stopped(report, message), do: {:error, %Error{operation: :submission, message: message}, report}
  defp fail!(message), do: raise(Error, operation: :preflight, message: message)
  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
