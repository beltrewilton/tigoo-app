defmodule TigooServer.Fe.TestInvoices do
  @moduledoc "Tenant-owned POS test documents; never writes operational sale data."
  import Ecto.Query
  alias TigooServer.{Repo, Tenants}
  alias TigooServer.Fe.{TestInvoice, TestInvoiceDocument}
  alias TigooServer.Retaily.{Sequence, User}

  @types ~w(31 32 33 34 41 43 44 45 46 47)
  @checkout_codes ~w(TEST_E31 TEST_E32 TEST_E44 TEST_E45 TEST_E46)
  def sequence_codes, do: Enum.map(@types, &("TEST_E" <> &1))
  def checkout_codes, do: @checkout_codes

  def options(tenant) do
    Repo.all(from(s in Sequence, where: s.code in ^@checkout_codes,
      order_by: s.code, select: %{code: s.code, name: s.name}), prefix: tenant)
  end

  def config(tenant, operation \\ :checkout) do
    with true <- Tenants.exists?(tenant),
         [company] <- Repo.all(from(c in TigooServer.Accounts.Company,
           where: c.active == true, limit: 2), prefix: tenant),
         :ok <- validate_company(company, operation),
         {:ok, signing} <- TigooServer.Fe.Credentials.for_tenant(tenant) do
      {:ok, %{"issuer_rnc" => String.trim(company.rnc), "issuer_name" => String.trim(company.company_name),
        "issuer_address" => String.trim(company.address || ""),
        "sequence_expiry" => if(company.ecf_test_sequence_expiry, do: Date.to_iso8601(company.ecf_test_sequence_expiry)),
        "p12_path" => signing.p12_path, "credentials_file" => signing.credentials_file,
        "artifact_directory" => Application.fetch_env!(:tigoo_server, :pos_ecf_test_artifact_directory)}}
    else
      {:error, {:ecf_test_not_configured, _}} = error -> error
      {:error, :signing_identity_unavailable} ->
        configuration_error("The company's eCF Test signing identity or credentials file is unavailable. Check the tenant's signing directory.")
      _ -> configuration_error("Exactly one active company is required for eCF Test in this tenant.")
    end
  end

  defp validate_company(company, operation) do
    cond do
      not is_binary(company.rnc) or not Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, String.trim(company.rnc)) ->
        configuration_error("Set a valid issuer RNC in this tenant's company record.")
      not is_binary(company.company_name) or String.trim(company.company_name) == "" ->
        configuration_error("Set the issuer's legal name in this tenant's company record.")
      operation == :checkout and (not is_binary(company.address) or String.trim(company.address) == "") ->
        configuration_error("Set the issuer address in Company settings before issuing an eCF Test invoice.")
      operation == :checkout and not company.ecf_test_sequences_ready ->
        configuration_error("Reconcile the test sequence counters, then enable their readiness in Company settings.")
      operation == :checkout and not valid_sequence_expiry?(company.ecf_test_sequence_expiry) ->
        configuration_error("Set a valid, unexpired eCF Test sequence expiry in Company settings.")
      true -> :ok
    end
  end

  defp configuration_error(message), do: {:error, {:ecf_test_not_configured, message}}

  defp valid_sequence_expiry?(%Date{} = expiry) do
    today = DateTime.utc_now() |> DateTime.add(-14_400) |> DateTime.to_date()
    Date.compare(expiry, today) != :lt
  end
  defp valid_sequence_expiry?(_), do: false

  def create(scope, checkout, snapshot, attrs) do
    request = Map.get(attrs, "idempotency_key", Map.get(attrs, :idempotency_key))
    with {:ok, request_id} <- Ecto.UUID.cast(request),
         {:ok, config} <- config(scope.tenant) do
      hash = attrs |> Map.drop(["idempotency_key", :idempotency_key]) |> Jason.encode!()
        |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
      # All requests for this employee serialize with mode changes and duplicate clicks.
      Repo.transaction(fn ->
        user = Repo.one(from(u in User, where: u.id == ^scope.actor_id, lock: "FOR UPDATE"), prefix: scope.tenant)
        unless user && user.is_active == 1 && user.ecf_test_enabled, do: Repo.rollback(:ecf_mode_changed)
        existing = Repo.get_by(TestInvoice, [user_id: user.id, request_id: request_id], prefix: scope.tenant)
        if existing do
          if existing.snapshot["request_hash"] != hash, do: Repo.rollback(:idempotency_conflict)
          response(existing)
        else
          sequence = Repo.one(from(s in Sequence, where: s.code == ^checkout.sequence_type, lock: "FOR UPDATE"), prefix: scope.tenant)
          unless sequence && sequence.code in @checkout_codes && sequence.increment_by == 1 &&
              sequence.fill == 10 && sequence.current_seq >= 0 && sequence.current_seq < 9_999_999_999 &&
              sequence.prefix == String.replace_prefix(sequence.code, "TEST_", ""),
            do: Repo.rollback(:invalid_ecf_test_sequence)
          next = sequence.current_seq + 1
          encf = sequence.prefix <> String.pad_leading(Integer.to_string(next), 10, "0")
          snapshot = snapshot |> Map.merge(%{sequence_type: checkout.sequence_type, request_hash: hash,
            batch_path: Path.join([Path.expand(config["artifact_directory"]), scope.tenant, request_id]),
            issuer_name: config["issuer_name"], issuer_address: config["issuer_address"],
            sequence_expiry: config["sequence_expiry"], issued_on: DateTime.utc_now() |> DateTime.add(-14_400) |> DateTime.to_date()})
            |> Jason.encode!() |> Jason.decode!()
          invoice = %TestInvoice{user_id: user.id, store_id: checkout.store_id, request_id: request_id,
            issuer_rnc: config["issuer_rnc"], encf: encf, snapshot: snapshot}
          case TestInvoiceDocument.validate(invoice) do
            :ok -> :ok
            {:error, message} -> Repo.rollback({:ecf_document, message})
          end
          sequence |> Ecto.Changeset.change(current_seq: next) |> Repo.update!(prefix: scope.tenant)
          invoice |> Repo.insert!(prefix: scope.tenant) |> response()
        end
      end)
    else
      :error -> {:error, :ecf_test_idempotency_key_required}
      error -> error
    end
  end

  def enabled?(%{actor: :employee, actor_id: id, tenant: tenant}) do
    Tenants.exists?(tenant) and Repo.exists?(from(u in User,
      where: u.id == ^id and u.is_active == 1 and u.ecf_test_enabled == true), prefix: tenant)
  end
  def enabled?(_), do: false

  def history(scope, before_id \\ nil) do
    if enabled?(scope) do
      query = from(i in TestInvoice, where: i.user_id == ^scope.actor_id, order_by: [desc: i.id], limit: 51)
      query = if is_integer(before_id), do: from(i in query, where: i.id < ^before_id), else: query
      records = Repo.all(query, prefix: scope.tenant)
      page = Enum.take(records, 50)
      {:ok, %{invoices: Enum.map(page, &response/1),
        next: if(length(records) > 50, do: List.last(page).id)}}
    else
      {:error, :forbidden}
    end
  end

  def track_id(invoice) do
    entry = get_in(invoice.report, ["entries", invoice.sequence]) || %{}
    entry["track_id"] || get_in(entry, ["upload_response", "trackId"]) || get_in(entry, ["result", "trackId"])
  end

  # Explicit status consultation only: this action never posts or requeues XML.
  def refresh_track(scope, "ecf-test-" <> id), do: refresh_track(scope, id)
  def refresh_track(scope, id) do
    with true <- enabled?(scope),
         {id, ""} <- Integer.parse(to_string(id)),
         true <- id > 0 do
      Repo.checkout(fn ->
        %{rows: [[locked?]]} = Repo.query!("SELECT pg_try_advisory_lock(hashtext($1), $2::integer)", ["pos-ecf-test:#{scope.tenant}", id])
        if locked? do
          try do
            invoice = Repo.get_by(TestInvoice, [id: id, user_id: scope.actor_id], prefix: scope.tenant)
            if invoice, do: query_track(scope, invoice), else: {:error, :not_found}
          after
            Repo.query!("SELECT pg_advisory_unlock(hashtext($1), $2::integer)", ["pos-ecf-test:#{scope.tenant}", id])
          end
        else
          {:error, :ecf_busy}
        end
      end, timeout: :infinity)
    else
      _ -> {:error, :forbidden}
    end
  rescue
    _ -> {:error, :ecf_status_unavailable}
  end

  defp query_track(scope, invoice) do
    alias TigooServer.Fe.Client
    track = track_id(response(invoice))
    with true <- is_binary(track) and track != "",
         {:ok, settings} <- config(scope.tenant, :submission),
         true <- invoice.environment == "testecf" and invoice.issuer_rnc == settings["issuer_rnc"],
         client <- Client.new(issuer_rnc: invoice.issuer_rnc, environment: "testecf",
           p12_path: settings["p12_path"], credentials_file: settings["credentials_file"]),
         {:ok, body, _client} <- Client.result(client, track),
         true <- body["trackId"] == track and body["encf"] == invoice.encf and
           body["rnc"] == invoice.issuer_rnc do
      status = Client.status(body)
      # Preserve the last known fiscal state on an unrecognized/not-found query.
      state = if status in [:accepted, :accepted_conditional, :rejected, :pending],
        do: Atom.to_string(status), else: invoice.state
      entry = get_in(invoice.report, ["entries", invoice.encf]) || %{}
      entry = Map.merge(entry, %{"result" => body, "track_id" => track, "state" => state})
      report = Map.put(invoice.report, "entries", Map.put(invoice.report["entries"] || %{}, invoice.encf, entry))
      Repo.transaction(fn ->
        updated = invoice |> Ecto.Changeset.change(state: state, report: report, error: nil) |> Repo.update!(prefix: scope.tenant)
        Repo.insert_all("fe_test_submission_attempts", [%{invoice_id: invoice.id, state: state, report: report,
          error: nil, inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)}], prefix: scope.tenant)
        response(updated)
      end)
    else
      false -> {:error, :ecf_track_unavailable}
      {:error, %TigooServer.Fe.Client.Error{}} -> {:error, :ecf_status_unavailable}
      error -> error
    end
  end

  def posted_xml(scope, "ecf-test-" <> id), do: posted_xml(scope, id)
  def posted_xml(scope, id) do
    with true <- enabled?(scope),
         {id, ""} <- Integer.parse(to_string(id)),
         %TestInvoice{} = invoice <- Repo.get_by(TestInvoice, [id: id, user_id: scope.actor_id], prefix: scope.tenant),
         %{} = entry <- get_in(invoice.report, ["entries", invoice.encf]),
         true <- entry["kind"] in ["ecf", "rfce"],
         relative when is_binary(relative) <- entry["file"],
         hash when is_binary(hash) <- entry["sha256"],
         root when is_binary(root) <- invoice.snapshot["batch_path"],
         root <- Path.expand(root),
         path <- Path.expand(relative, root),
         true <- String.starts_with?(path, root <> "/"),
         {:ok, %{size: size}} when size <= 5_000_000 <- File.stat(path),
         {:ok, xml} <- File.read(path),
         true <- TigooServer.Fe.Generation.Artifact.sha256(xml) == hash do
      {:ok, %{id: "ecf-test-#{invoice.id}", xml: xml, sha256: hash, filename: Path.basename(path), kind: entry["kind"],
        sequence: invoice.encf, state: entry["state"],
        has_receipt: is_map(entry["upload_response"]) or is_map(entry["result"])}}
    else
      _ -> {:error, :ecf_xml_unavailable}
    end
  rescue
    _ -> {:error, :ecf_xml_unavailable}
  end

  def verification_url(scope, id) do
    alias TigooServer.Fe.Generation.{Artifact, Xml}

    with {:ok, _} <- posted_xml(scope, id),
         {:ok, invoice} <- get(scope, id),
         true <- invoice.environment in ["testecf", "certecf", "ecf"],
         {record_id, ""} <- invoice.id |> String.replace_prefix("ecf-test-", "") |> Integer.parse(),
         %TestInvoice{} = record <- Repo.get_by(TestInvoice, [id: record_id, user_id: scope.actor_id], prefix: scope.tenant),
         root <- Path.expand(record.snapshot["batch_path"]),
         {:ok, bytes} <- File.read(Path.join(root, "manifest.json")),
         {:ok, manifest} <- Jason.decode(bytes),
         %{} = doc <- Enum.find(manifest["documents"], &(&1["encf"] == record.encf)),
         path <- Path.expand(doc["ecf_file"], root),
         true <- String.starts_with?(path, root <> "/"),
         {:ok, %{size: size}} when size <= 5_000_000 <- File.stat(path),
         {:ok, xml} <- File.read(path),
         true <- Artifact.sha256(xml) == doc["ecf_sha256"] do
      signed = Xml.parse!(xml)
      params = [{"RncEmisor", Xml.value(signed, ~w(Encabezado Emisor RNCEmisor))},
        {"ENCF", Xml.value(signed, ~w(Encabezado IdDoc eNCF))},
        {"MontoTotal", Xml.value(signed, ~w(Encabezado Totales MontoTotal))},
        {"CodigoSeguridad", String.slice(Xml.signature!(signed).value, 0, 6)}]
      {host, endpoint, params} = if doc["small_consumption"] == true do
        {"fc.dgii.gov.do", "ConsultaTimbreFC", params}
      else
        {"ecf.dgii.gov.do", "ConsultaTimbre", params ++ [
          {"RncComprador", Xml.value(signed, ~w(Encabezado Comprador RNCComprador)) || ""},
          {"FechaEmision", Xml.value(signed, ~w(Encabezado Emisor FechaEmision))},
          {"FechaFirma", Xml.value(signed, ["FechaHoraFirma"])}]}
      end
      {:ok, %{url: "https://#{host}/#{invoice.environment}/#{endpoint}?" <> URI.encode_query(params, :rfc3986), sequence: invoice.sequence}}
    else
      _ -> {:error, :ecf_xml_unavailable}
    end
  rescue
    _ -> {:error, :ecf_xml_unavailable}
  end

  def latest(scope) do
    query = from(i in TestInvoice, where: i.user_id == ^scope.actor_id, order_by: [desc: i.id], limit: 1)
    case Repo.one(query, prefix: scope.tenant) do
      nil -> nil
      invoice -> response(invoice)
    end
  end

  def retry(scope, "ecf-test-" <> id), do: retry(scope, id)
  def retry(scope, id) do
    if enabled?(scope) do
      Repo.transaction(fn ->
        user = Repo.one(from(u in User, where: u.id == ^scope.actor_id, lock: "FOR UPDATE"), prefix: scope.tenant)
        unless user && user.is_active == 1 && user.ecf_test_enabled, do: Repo.rollback(:forbidden)
        invoice = Repo.one(from(i in TestInvoice, where: i.id == ^id and i.user_id == ^scope.actor_id, lock: "FOR UPDATE"), prefix: scope.tenant)
        unless invoice, do: Repo.rollback(:not_found)
        # Only known pre-upload failures can be retried; uncertain/rejected
        # documents still require reconciliation instead of another POST.
        unless invoice.state == "failed", do: Repo.rollback(:ecf_retry_requires_reconciliation)
        case config(scope.tenant) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end
        invoice |> Ecto.Changeset.change(state: "queued", error: nil) |> Repo.update!(prefix: scope.tenant) |> response()
      end)
    else
      {:error, :forbidden}
    end
  end

  def get(scope, "ecf-test-" <> id), do: get(scope, id)
  def get(scope, id) do
    query = from(i in TestInvoice, where: i.id == ^id)
    query = if scope.actor == :admin, do: query, else: from(i in query, where: i.user_id == ^scope.actor_id)
    case Repo.one(query, prefix: scope.tenant) do
      nil -> {:error, :not_found}
      invoice -> {:ok, response(invoice)}
    end
  end

  defp receipt(invoice) do
    s = invoice.snapshot
    details = s["ecf"] || %{}
    client = s["client"]
    client = if is_binary(details["ecf_buyer_id"]) and String.trim(details["ecf_buyer_id"]) != "",
      do: Map.put(client, "document_id", details["ecf_buyer_id"]), else: client
    client = if is_binary(details["ecf_buyer_name"]) and String.trim(details["ecf_buyer_name"]) != "",
      do: Map.put(client, "name", details["ecf_buyer_name"]), else: client
    amount = Decimal.new(s["totals"]["amount"])
    paid = Enum.reduce(s["payments"], Decimal.new(0), fn payment, sum -> Decimal.add(sum, payment["amount"]) end)
    %{id: "ecf-test-#{invoice.id}", ecf_test: true, sequence: invoice.encf,
      sequence_type: s["sequence_type"], client: client, login: s["login"],
      status: s["status"], invoice_status: "test", date_create: invoice.inserted_at,
      due_date: s["due_date"], amount: amount, sub: s["totals"]["sub"],
      tax_amount: s["totals"]["tax"], discount: s["totals"]["discount"],
      delivery_charge: s["delivery_charge"], total_paid: paid,
      due_balance: Decimal.max(Decimal.sub(amount, paid), 0),
      change_amount: Decimal.max(Decimal.sub(paid, amount), 0),
      additional_info: "eCF Test — " <> (s["additional_info"] || ""),
      payments: s["payments"], lines: Enum.map(s["lines"], fn line ->
        %{product_id: line["product_id"], product: %{name: line["name"], code: line["code"]},
          quantity: line["quantity"], amount: line["price"], discount: line["discount"],
          ecf_tax_indicator: TigooServer.Fe.SaleFiscal.indicator(s["sequence_type"], line["tax"]),
          total_amount: line["total"]}
      end) ++ delivery_receipt_line(s)}
  end

  defp delivery_receipt_line(snapshot) do
    delivery = Decimal.new(snapshot["delivery_charge"])
    if Decimal.positive?(delivery) do
      [%{product_id: nil, product: %{name: "Entrega", code: "DELIVERY"}, quantity: 1,
        amount: delivery, discount: Decimal.new(0), total_amount: delivery,
        ecf_tax_indicator: TigooServer.Fe.SaleFiscal.indicator(snapshot["sequence_type"], "1")}]
    else
      []
    end
  end

  def response(invoice) do
    %{id: "ecf-test-#{invoice.id}", resource_type: "ecf_test_invoice", ecf_test: true,
      status_url: "/api/sales/ecf-tests/ecf-test-#{invoice.id}",
      issuer_rnc: invoice.issuer_rnc, environment: invoice.environment, sequence: invoice.encf,
      sequence_type: invoice.snapshot["sequence_type"], state: invoice.state,
      report: invoice.report, error: invoice.error, receipt: receipt(invoice), inserted_at: invoice.inserted_at}
  end
end
