defmodule TigooServer.Fe.TestInvoiceWorker do
  @moduledoc "Small durable scanner over tenant test invoices, using the existing submission journal."
  use GenServer
  import Ecto.Query
  require Logger
  alias TigooServer.{Repo, Tenants}
  alias TigooServer.Fe.{Client, Generation, Submission, TestInvoice, TestInvoiceDocument, TestInvoices}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def init(_opts) do
    Process.send_after(self(), :scan, 5_000)
    {:ok, nil}
  end

  def handle_info(:scan, state) do
    Tenants.list() |> Enum.each(&scan/1)
    Process.send_after(self(), :scan, 5_000)
    {:noreply, state}
  end

  defp scan(tenant) do
    %{rows: [[migrated?]]} = Repo.query!(
      "SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = $1 AND table_name = 'fe_test_invoices')",
      [Triplex.to_prefix(tenant)])
    if migrated?, do: scan_invoices(tenant)
  rescue
    _ -> Logger.warning("POS eCF scan unavailable for tenant #{tenant}")
  end

  defp scan_invoices(tenant) do
    ids = Repo.all(from(i in TestInvoice, where: i.state in ["queued", "pending"],
      order_by: i.updated_at, limit: 10, select: i.id), prefix: tenant)
    Enum.each(ids, &process(tenant, &1))
  rescue
    _ -> Logger.warning("POS eCF scan unavailable for tenant #{tenant}")
  end

  defp process(tenant, id) do
    # A session lock coordinates application nodes without a transaction around HTTP.
    # If a node dies, PostgreSQL releases the lock and the next scan resumes the journal.
    Repo.checkout(fn ->
      %{rows: [[locked?]]} = Repo.query!("SELECT pg_try_advisory_lock(hashtext($1), $2::integer)", ["pos-ecf-test:#{tenant}", id])
      if locked? do
        try do
          invoice = Repo.get!(TestInvoice, id, prefix: tenant)
          if invoice.state in ["queued", "pending"], do: submit(tenant, invoice)
        after
          Repo.query!("SELECT pg_advisory_unlock(hashtext($1), $2::integer)", ["pos-ecf-test:#{tenant}", id])
        end
      end
    end, timeout: :infinity)
  rescue
    _ -> Logger.warning("POS eCF processing interrupted for tenant #{tenant}, document #{id}; journal retained")
  end

  defp submit(tenant, invoice) do
    with {:ok, config} <- TestInvoices.config(tenant, :submission),
         true <- invoice.environment in ["testecf", "certecf"] and invoice.issuer_rnc == config["issuer_rnc"] do
      purpose = TestInvoices.submission_purpose(invoice.environment)
      opts = [issuer_rnc: invoice.issuer_rnc, p12_path: config["p12_path"],
        credentials_file: config["credentials_file"], purpose: purpose,
        strict_arithmetic: true]

      case prepare_batch(tenant, invoice, opts) do
        {:ok, directory} -> submit_batch(tenant, invoice, directory, opts, purpose)
        {:error, message} ->
          if unsubmitted?(invoice) do
            save(tenant, invoice, "failed", invoice.report, "Generation failed before DGII submission: " <> message)
          else
            save(tenant, invoice, "unknown", invoice.report,
              "Batch preparation failed: #{message}. A prior submission may exist; reconcile before retrying.")
          end
      end
    else
      _ ->
        state = if unsubmitted?(invoice), do: "failed", else: "unknown"
        save(tenant, invoice, state, invoice.report, "Tenant eCF configuration is unavailable, environment is unsupported or issuer changed")
    end
  rescue
    error ->
      log_failure(tenant, invoice, :preparation, error, __STACKTRACE__)
      save(tenant, invoice, "unknown", invoice.report,
        "Invoice processing interrupted. Inspect the retained batch/journal before retrying.")
  end

  defp prepare_batch(tenant, invoice, opts) do
    directory = invoice.snapshot["batch_path"]
    unless File.regular?(Path.join(directory, "manifest.json")) do
      # Generation is offline; no DGII request happens before this returns.
      File.mkdir_p!(Path.dirname(directory))
      source = directory <> ".source.json"
      bytes = Jason.encode!(invoice.snapshot)
      case File.write(source, bytes, [:exclusive]) do
        :ok -> :ok
        {:error, :eexist} ->
          unless (source |> File.read!() |> Jason.decode!()) == invoice.snapshot,
            do: TigooServer.Fe.Generation.Error.fail!(:source, "POS source snapshot changed; reconcile the retained source file")
        {:error, reason} -> raise File.Error, reason: reason, action: "write", path: source
      end
      Generation.generate_rows!([TestInvoiceDocument.row(invoice)],
        Keyword.merge(opts, source_path: source, source_kind: :pos, output: directory))
    end
    {:ok, directory}
  rescue
    error ->
      log_failure(tenant, invoice, :generation, error, __STACKTRACE__)
      message = case error do
        %TigooServer.Fe.Generation.Error{} -> Exception.message(error)
        %File.Error{} -> "Cannot #{error.action} generation files: #{:file.format_error(error.reason)}"
        _ -> "Unexpected generation error (#{inspect(error.__struct__)}). Check the server log for its location."
      end
      {:error, message}
  end

  defp unsubmitted?(invoice) do
    directory = invoice.snapshot["batch_path"]
    # Never make a pending or previously journaled invoice automatically retryable.
    invoice.state == "queued" and is_binary(directory) and
      map_size(invoice.report["entries"] || %{}) == 0 and
      Path.wildcard(Path.join(directory, "submission-*")) == []
  end

  defp submit_batch(tenant, invoice, directory, opts, purpose) do
      client = Client.new(Keyword.put(opts, :environment, invoice.environment))
      result = Submission.run(directory, client, expected_purpose: purpose, poll_attempts: 1)
      {report, error, operation} = case result do
        {:ok, report} -> {report, nil, nil}
        {:error, error, report} -> {report || %{}, Exception.message(error), error.operation}
      end
      entry = get_in(report, ["entries", invoice.encf]) || %{}
      state = case entry["state"] do
        status when status in ["accepted", "accepted_conditional", "rejected", "pending"] -> status
        "not_sent" -> "failed"
        nil when operation in [:seed, :authenticate] -> "failed"
        _ -> "unknown"
      end
      save(tenant, invoice, state, report, error)
  rescue
    error ->
      log_failure(tenant, invoice, :submission, error, __STACKTRACE__)
      save(tenant, invoice, "unknown", invoice.report,
        "Submission interrupted. Inspect the retained batch/journal before retrying.")
  end

  defp log_failure(tenant, invoice, phase, error, stacktrace) do
    # Do not log snapshots, passwords, credentials or native command output.
    stage = Map.get(error, :stage)
    stacktrace = Enum.map(stacktrace, fn
      {module, function, args, location} when is_list(args) -> {module, function, length(args), location}
      frame -> frame
    end)
    Logger.error("POS eCF #{phase} failed tenant=#{tenant} invoice=#{invoice.id} " <>
      "exception=#{inspect(error.__struct__)} stage=#{inspect(stage)}\n" <> Exception.format_stacktrace(stacktrace))
  end

  defp save(tenant, invoice, state, report, error) do
    Repo.transaction(fn ->
      invoice |> Ecto.Changeset.change(state: state, report: report, error: error) |> Repo.update!(prefix: tenant)
      Repo.insert_all("fe_test_submission_attempts", [%{invoice_id: invoice.id, state: state,
        report: report, error: error, inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)}], prefix: tenant)
    end)
  end
end
