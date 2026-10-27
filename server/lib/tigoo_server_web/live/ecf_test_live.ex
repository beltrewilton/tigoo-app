defmodule TigooServerWeb.EcfTestLive do
  use TigooServerWeb, :live_view
  import TigooServerWeb.PosLayoutComponents
  alias TigooServer.{Authentication, TenantContext}
  alias TigooServer.Fe.TestInvoices
  alias TigooServer.Retaily.InventoryContext

  def mount(_params, session, socket) do
    with token when is_binary(token) <- session["user_token"],
         {:ok, scope} <- Authentication.authenticate(token),
         true <- TestInvoices.enabled?(scope),
         _ <- TenantContext.put_tenant(scope.tenant),
         {:ok, stores} <- InventoryContext.stores(scope) do
      if connected?(socket), do: Phoenix.PubSub.subscribe(TigooServer.PubSub, "ecf-mode:#{scope.tenant}:#{scope.actor_id}")
      {:ok, assign(socket, page_title: "eCF Test history", scope: scope, stores: stores,
        store_id: session["store_id"] || (List.first(stores) && hd(stores).id),
        invoices: [], next: nil, before_id: nil, refreshing: nil, inspection: nil, history_timer: nil, status: "")}
    else
      _ -> {:ok, socket |> put_flash(:error, "eCF Test must be enabled to view this page.") |> redirect(to: ~p"/pos")}
    end
  end

  def handle_params(params, _uri, socket) do
    before_id = case Integer.parse(params["before"] || "") do
      {id, ""} when id > 0 -> id
      _ -> nil
    end
    socket = socket |> assign(before_id: before_id, inspection: nil) |> load_history()
    socket = if params["inspect"], do: inspect_invoice(socket, params["inspect"]), else: socket
    {:noreply, schedule_history(socket)}
  end

  def handle_event("change_store", %{"store_id" => id}, socket) do
    if Enum.any?(socket.assigns.stores, &(to_string(&1.id) == id)),
      do: {:noreply, assign(socket, :store_id, id)}, else: {:noreply, socket}
  end

  def handle_event("inspect_xml", %{"id" => id}, socket),
    do: {:noreply, inspect_invoice(socket, id)}

  def handle_event("close_xml_inspector", _, socket),
    do: {:noreply, assign(socket, :inspection, nil)}

  def handle_event("reload_history", _, socket), do: {:noreply, load_history(socket)}

  def handle_event("refresh_track", %{"id" => id}, socket) do
    invoice = if socket.assigns.inspection && socket.assigns.inspection.invoice.id == id,
      do: socket.assigns.inspection.invoice, else: Enum.find(socket.assigns.invoices, &(&1.id == id))
    if is_nil(socket.assigns.refreshing) and invoice && TestInvoices.track_id(invoice) do
      scope = socket.assigns.scope
      {:noreply, socket |> assign(refreshing: id, status: "Fetching DGII status…")
        |> start_async(:refresh_track, fn -> TestInvoices.refresh_track(scope, id) end)}
    else
      {:noreply, socket}
    end
  end

  def handle_async(:refresh_track, {:ok, {:ok, invoice}}, socket) do
    socket = socket |> assign(refreshing: nil, status: "") |> load_history()
    socket = if socket.assigns.inspection && socket.assigns.inspection.invoice.id == invoice.id,
      do: assign(socket, :inspection, %{socket.assigns.inspection | invoice: invoice}), else: socket
    {:noreply, socket}
  end
  def handle_async(:refresh_track, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, refreshing: nil, status: error_message(reason))}
  def handle_async(:refresh_track, {:exit, _}, socket),
    do: {:noreply, assign(socket, refreshing: nil, status: "Status consultation failed. The saved response is retained.")}

  def handle_info(:refresh_history, socket),
    do: {:noreply, socket |> assign(:history_timer, nil) |> load_history()}

  def handle_info({:ecf_test_mode, false}, socket), do: {:noreply, redirect(socket, to: ~p"/pos")}
  def handle_info({:ecf_test_mode, true}, socket), do: {:noreply, socket}

  defp load_history(socket) do
    case TestInvoices.history(socket.assigns.scope, socket.assigns.before_id) do
      {:ok, page} ->
        socket = assign(socket, invoices: page.invoices, next: page.next)
        socket = if socket.assigns.inspection do
          case Enum.find(page.invoices, &(&1.id == socket.assigns.inspection.invoice.id)) do
            nil -> socket
            invoice ->
              inspection = %{socket.assigns.inspection | invoice: invoice}
              inspection = if is_nil(inspection.artifact) do
                case TestInvoices.posted_xml(socket.assigns.scope, invoice.id) do
                  {:ok, artifact} -> %{inspection | artifact: artifact, error: nil}
                  _ -> inspection
                end
              else
                inspection
              end
              assign(socket, :inspection, inspection)
          end
        else
          socket
        end
        schedule_history(socket)
      _ -> redirect(socket, to: ~p"/pos")
    end
  end

  defp schedule_history(socket) do
    pending? = Enum.any?(socket.assigns.invoices, &(&1.state in ["queued", "pending"]))
    if pending? and connected?(socket) and is_nil(socket.assigns.history_timer),
      do: assign(socket, :history_timer, Process.send_after(self(), :refresh_history, 3_000)), else: socket
  end

  def render(assigns) do
    ~H"""
    <.pos_layout id="ecf-test-history" class="pos-shell invoice-view" active_page={:ecf_tests}
      scope={@scope} stores={@stores} store_id={@store_id}>
      <section class="catalog-panel ecf-history-page" aria-labelledby="ecf-test-title">
        <header class="ecf-history-heading">
          <div><p class="ecf-xml-eyebrow">FISCAL WORKSPACE</p><h1 id="ecf-test-title">eCF Test history</h1>
          </div>
          <div class="ecf-history-heading-actions">
            <a class="btn" href={~p"/pos"}>Back to POS</a>
            <button class="btn" type="button" phx-click="reload_history">Reload list</button>
          </div>
        </header>
        <div class="ecf-history-status" role="status" aria-live="polite">
          <span :if={@refreshing} class="ecf-spinner" aria-hidden="true"></span>{@status}
        </div>
        <div class="ecf-history-table-card">
          <div class="ecf-history-table-heading"><span>Test invoices</span><small>{length(@invoices)} on this page · DOP</small></div>
          <div :if={@invoices == []} class="ecf-history-empty"><strong>No test invoices yet</strong><p>Completed test checkouts will appear here with their DGII responses.</p></div>
          <div :if={@invoices != []} class="ecf-history-table-scroll">
            <table class="ecf-history-table">
              <thead><tr><th>Invoice</th><th>Buyer</th><th class="is-numeric">Amount</th><th>Status</th><th>Track ID</th><th>DGII receipt</th><th class="ecf-history-actions-heading">Actions</th></tr></thead>
              <tbody>
                <tr :for={invoice <- @invoices} id={invoice.id}
                  class={[@inspection && @inspection.invoice.id == invoice.id && "is-inspected"]}
                  aria-busy={@refreshing == invoice.id}>
                  <td><strong class="ecf-history-sequence">{invoice.sequence}</strong><small title={to_string(invoice.inserted_at)}>{created_at(invoice.inserted_at)}</small></td>
                  <td><span class="ecf-history-buyer">{invoice.receipt.client["name"] || "—"}</span><small>{invoice.receipt.client["document_id"] || "—"}</small></td>
                  <td class="is-numeric ecf-history-amount">{Decimal.to_string(Decimal.round(invoice.receipt.amount, 2), :normal)}</td>
                  <td>
                    <span class="ecf-status-badge" data-state={invoice.state}>
                      <span :if={invoice.state in ["queued", "pending"] or @refreshing == invoice.id} class="ecf-spinner" aria-hidden="true"></span>
                      {status_label(invoice.state)}
                    </span>
                    <small class="ecf-history-message" title={messages(invoice)}>{messages(invoice)}</small>
                  </td>
                  <td><code class="ecf-history-track" title={TestInvoices.track_id(invoice)}>{TestInvoices.track_id(invoice) || "—"}</code></td>
                  <td>
                    <span class="ecf-history-received">{result(invoice)["fechaRecepcion"] || "Awaiting receipt"}</span>
                    <small>RNC {result(invoice)["rnc"] || invoice.issuer_rnc} · Code {result(invoice)["codigo"] || "—"}</small>
                    <small :if={!is_nil(result(invoice)["secuenciaUtilizada"])}>Sequence {if result(invoice)["secuenciaUtilizada"], do: "used", else: "not used"}</small>
                  </td>
                  <td>
                    <div class="ecf-history-row-actions">
                      <button class="ecf-history-inspect" type="button" phx-click="inspect_xml" phx-value-id={invoice.id}
                        aria-haspopup="dialog" aria-controls="ecf-row-inspector"
                        aria-expanded={not is_nil(@inspection) and @inspection.invoice.id == invoice.id}>Inspect</button>
                      <a id={"dgii-popup-#{invoice.id}"} phx-hook="DgiiPopup" class="ecf-history-refresh" href={~p"/pos/ecf-tests/#{invoice.id}/dgii"}
                        target="_blank" rel="noopener noreferrer" title="Verify invoice on DGII (popup)"
                        aria-label={"Verify #{invoice.sequence} on DGII (popup)"}>
                        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
                          <circle cx="12" cy="12" r="9" /><ellipse cx="12" cy="12" rx="4" ry="9" /><path d="M3 12h18M5 6h14M5 18h14" />
                        </svg>
                      </a>
                      <button class="ecf-history-refresh" type="button" phx-click="refresh_track" phx-value-id={invoice.id}
                        disabled={not is_nil(@refreshing) or is_nil(TestInvoices.track_id(invoice))}
                        title={if TestInvoices.track_id(invoice), do: "Fetch DGII status by track ID", else: "No track ID available; RFCE responses are returned directly"}
                        aria-label={"Fetch DGII status for #{invoice.sequence}"}>
                        <span :if={@refreshing == invoice.id} class="ecf-spinner" aria-hidden="true"></span>
                        <svg :if={@refreshing != invoice.id} width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                          <path d="M20 7v5h-5M4 17v-5h5" /><path d="M6 7a7 7 0 0 1 12-1l2 3M4 15l2 3a7 7 0 0 0 12-1" />
                        </svg>
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <dialog :if={@inspection} id="ecf-row-inspector" class="ecf-row-inspector"
          open phx-hook="EcfRowInspector" data-anchor={@inspection.invoice.id}
          aria-modal="true" aria-labelledby="ecf-inspector-title">
          <header class="ecf-inspector-heading">
            <div class="ecf-inspector-title-line"><p class="ecf-xml-eyebrow">DGII EXCHANGE</p>
              <h2 id="ecf-inspector-title">{@inspection.invoice.sequence}</h2>
            </div>
            <button class="btn" type="button" phx-click="close_xml_inspector" aria-label="Close request and response inspector">✕</button>
          </header>
          <div class="ecf-inspector-columns">
            <section class="ecf-inspector-request" aria-labelledby="ecf-request-title">
              <div class="ecf-inspector-panel-heading">
                <h3 id="ecf-request-title">Request <span>XML</span></h3>
                <a :if={@inspection.artifact} class="ecf-inspector-download"
                  href={~p"/pos/ecf-tests/#{@inspection.invoice.id}/xml/download"}>Download original ↓</a>
              </div>
              <p :if={@inspection.error} class="ecf-xml-notice is-warning" role="alert">{@inspection.error}</p>
              <div :if={@inspection.artifact} id={"row-xml-#{@inspection.invoice.id}"} class="ecf-xml-workspace"
                phx-hook="XmlViewer" data-xml-source={Base.encode64(@inspection.artifact.xml)}
                data-xml-hash={@inspection.artifact.sha256}>
                <p class="ecf-inspector-file">{@inspection.artifact.filename}
                  <span class="ecf-xml-verified">✓ Checksum verified</span></p>
                <p :if={@inspection.artifact.kind == "rfce"} class="ecf-xml-notice">This request is the RFCE summary sent to DGII.</p>
                <p :if={!@inspection.artifact.has_receipt} class="ecf-xml-notice is-warning">This upload has no confirmed DGII receipt.</p>
                <div class="ecf-xml-editor">
                  <div class="ecf-xml-toolbar">
                    <span class="ecf-xml-toolbar-label">Formatted XML</span>
                    <div class="ecf-xml-tools">
                      <button type="button" data-xml-wrap aria-pressed="true">Wrap lines</button>
                      <button type="button" data-copy-xml>Copy original</button>
                    </div>
                  </div>
                  <pre id={"row-xml-code-#{@inspection.invoice.id}"} class="ecf-xml-code is-wrapped"
                    data-xml-code phx-update="ignore" tabindex="0" aria-label="Exact submitted XML">{@inspection.artifact.xml}</pre>
                  <div class="ecf-xml-editor-footer"><span data-xml-lines>XML</span><span>UTF-8 · Read only</span>
                    <span data-xml-status role="status" aria-live="polite"></span></div>
                </div>
                <p class="ecf-xml-caption">Formatting is for display. Copy and download preserve the signed original.</p>
                <details class="ecf-xml-checksum"><summary>SHA-256</summary>
                  <div><code>{@inspection.artifact.sha256}</code><button type="button" data-copy-hash>Copy checksum</button></div>
                </details>
              </div>
            </section>
            <section class="ecf-inspector-response" aria-labelledby="ecf-response-title">
              <div class="ecf-inspector-panel-heading">
                <h3 id="ecf-response-title">Response <span>JSON</span></h3>
                <span class="ecf-status-badge" data-state={@inspection.invoice.state}>{status_label(@inspection.invoice.state)}</span>
                <button class="ecf-history-refresh" type="button" phx-click="refresh_track" phx-value-id={@inspection.invoice.id}
                  disabled={not is_nil(@refreshing) or is_nil(TestInvoices.track_id(@inspection.invoice))} aria-label="Fetch DGII response">
                  <span :if={@refreshing == @inspection.invoice.id} class="ecf-spinner" aria-hidden="true"></span>
                  <span :if={@refreshing != @inspection.invoice.id} aria-hidden="true">↻</span>
                </button>
              </div>
              <p class="ecf-inspector-track"><span>Track ID</span><code>{TestInvoices.track_id(@inspection.invoice) || "No track ID"}</code></p>
              <div class="ecf-inspector-json">
                <pre tabindex="0" aria-label="Saved DGII response">{Jason.encode!(result(@inspection.invoice), pretty: true)}</pre>
              </div>
              <details :if={upload_response(@inspection.invoice)} class="ecf-inspector-upload">
                <summary>Initial upload response</summary>
                <pre>{Jason.encode!(upload_response(@inspection.invoice), pretty: true)}</pre>
              </details>
              <p :if={@inspection.invoice.error} role="alert">{@inspection.invoice.error}</p>
              <p class="ecf-xml-caption">Saved DGII response for this invoice.</p>
            </section>
          </div>
        </dialog>
        <nav aria-label="Test invoice pages">
          <span class="ecf-history-page-note">Newest first · 50 invoices per page</span>
          <.link :if={@before_id} class="btn" patch={~p"/pos/ecf-tests"}>Newest</.link>
          <.link :if={@next} class="btn" patch={~p"/pos/ecf-tests?before=#{@next}"}>Older</.link>
        </nav>
      </section>
    </.pos_layout>
    """
  end

  defp inspect_invoice(socket, id) do
    with true <- TestInvoices.enabled?(socket.assigns.scope),
         "ecf-test-" <> number <- id,
         {number, ""} <- Integer.parse(number),
         true <- number > 0,
         {:ok, invoice} <- TestInvoices.get(socket.assigns.scope, number) do
      {artifact, error} = case TestInvoices.posted_xml(socket.assigns.scope, number) do
        {:ok, artifact} -> {artifact, nil}
        _ -> {nil, "The upload XML is unavailable or does not match its recorded checksum."}
      end
      assign(socket, :inspection, %{invoice: invoice, artifact: artifact, error: error})
    else
      _ -> assign(socket, :status, "This test invoice is unavailable.")
    end
  end

  defp upload_response(invoice), do: get_in(invoice.report, ["entries", invoice.sequence, "upload_response"])

  defp result(invoice) do
    entry = get_in(invoice.report, ["entries", invoice.sequence]) || %{}
    entry["result"] || entry["upload_response"] || %{}
  end

  defp messages(invoice) do
    case result(invoice)["mensajes"] do
      values when is_list(values) -> values |> Enum.flat_map(fn
        %{"valor" => value} when is_binary(value) -> if String.trim(value) == "", do: [], else: [value]
        _ -> []
      end) |> Enum.join("; ")
      _ -> ""
    end
  end

  defp created_at(%DateTime{} = value), do: value |> DateTime.add(-14_400) |> Calendar.strftime("%d %b %Y · %H:%M")
  defp created_at(value), do: to_string(value)
  defp status_label("accepted"), do: "Accepted"
  defp status_label("accepted_conditional"), do: "Conditional"
  defp status_label("rejected"), do: "Rejected"
  defp status_label("queued"), do: "Queued"
  defp status_label("pending"), do: "Pending"
  defp status_label("failed"), do: "Not sent"
  defp status_label(_), do: "Needs review"

  defp error_message(:ecf_busy), do: "This invoice is being processed. Try again shortly."
  defp error_message(:forbidden), do: "eCF Test access is no longer enabled."
  defp error_message({:ecf_test_not_configured, message}), do: message
  defp error_message(_), do: "DGII status is unavailable. The saved response is retained."
end
