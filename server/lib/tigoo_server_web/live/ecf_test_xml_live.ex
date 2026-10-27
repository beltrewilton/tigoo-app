defmodule TigooServerWeb.EcfTestXmlLive do
  use TigooServerWeb, :live_view
  import TigooServerWeb.PosLayoutComponents
  alias TigooServer.{Authentication, TenantContext}
  alias TigooServer.Fe.TestInvoices
  alias TigooServer.Retaily.InventoryContext

  def mount(%{"id" => id}, session, socket) do
    with token when is_binary(token) <- session["user_token"],
         {:ok, scope} <- Authentication.authenticate(token),
         true <- TestInvoices.enabled?(scope),
         _ <- TenantContext.put_tenant(scope.tenant),
         {:ok, stores} <- InventoryContext.stores(scope) do
      if connected?(socket), do: Phoenix.PubSub.subscribe(TigooServer.PubSub, "ecf-mode:#{scope.tenant}:#{scope.actor_id}")
      {artifact, error} = case TestInvoices.posted_xml(scope, id) do
        {:ok, artifact} -> {artifact, nil}
        _ -> {nil, "The uploaded XML is not available or its checksum does not match the submission record. Check the saved invoice artifacts."}
      end
      {:ok, assign(socket, page_title: "eCF Test submitted XML", scope: scope, stores: stores,
        store_id: session["store_id"] || (List.first(stores) && hd(stores).id), artifact: artifact, error: error)}
    else
      _ -> {:ok, redirect(socket, to: ~p"/pos")}
    end
  end

  def handle_event("change_store", %{"store_id" => id}, socket) do
    if Enum.any?(socket.assigns.stores, &(to_string(&1.id) == id)),
      do: {:noreply, assign(socket, :store_id, id)}, else: {:noreply, socket}
  end

  def handle_info({:ecf_test_mode, false}, socket), do: {:noreply, redirect(socket, to: ~p"/pos")}
  def handle_info({:ecf_test_mode, true}, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.pos_layout id="ecf-test-xml" class="pos-shell invoice-view" active_page={:ecf_tests}
      scope={@scope} stores={@stores} store_id={@store_id}>
      <section class="catalog-panel ecf-xml-page" aria-labelledby="ecf-xml-title">
        <a class="ecf-xml-back" href={~p"/pos/ecf-tests"}>
          <span aria-hidden="true">←</span> eCF Test history
        </a>
        <header class="ecf-xml-heading">
          <div>
            <p class="ecf-xml-eyebrow">DOCUMENT INSPECTOR</p>
            <h1 id="ecf-xml-title">Invoice XML</h1>
            <p class="ecf-xml-subtitle">The signed document used for this DGII test submission.</p>
          </div>
          <span class="ecf-xml-environment"><span aria-hidden="true"></span> eCF Test</span>
        </header>
        <div :if={@error} class="ecf-xml-notice is-warning" role="alert">{@error}</div>
        <div :if={@artifact} id="ecf-xml-viewer" class="ecf-xml-workspace" phx-hook="XmlViewer"
          data-xml-source={Base.encode64(@artifact.xml)} data-xml-hash={@artifact.sha256}>
          <div class="ecf-xml-document">
            <div class="ecf-xml-file-icon" aria-hidden="true">&lt;/&gt;</div>
            <div class="ecf-xml-file-info">
              <h2>{@artifact.sequence}</h2>
              <p>{@artifact.filename}</p>
            </div>
            <div class="ecf-xml-file-meta">
              <span class="ecf-xml-kind">{String.upcase(@artifact.kind)}</span>
              <span>{Float.round(byte_size(@artifact.xml) / 1024, 1)} KB</span>
            </div>
            <a class="btn ecf-xml-download" href={~p"/pos/ecf-tests/#{@artifact.id}/xml/download"}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                <path d="M12 3v12m-5-5 5 5 5-5M5 16v5h14v-5" />
              </svg>
              Download original
            </a>
          </div>
          <div class="ecf-xml-verification">
            <span class="ecf-xml-verified"><span aria-hidden="true">✓</span> Checksum verified</span>
            <span>Matches the saved upload record.</span>
          </div>
          <p :if={@artifact.kind == "rfce"} class="ecf-xml-notice">
            This submission used an RFCE summary. You are viewing that summary, rather than the associated full ECF.
          </p>
          <p :if={@artifact.state == "not_sent"} class="ecf-xml-notice is-warning">
            Sending did not complete. This is the prepared upload artifact.
          </p>
          <p :if={!@artifact.has_receipt and @artifact.state != "not_sent"} class="ecf-xml-notice is-warning">
            DGII receipt is unconfirmed. Review the saved response before retrying.
          </p>
          <div class="ecf-xml-editor">
            <div class="ecf-xml-toolbar">
              <span class="ecf-xml-toolbar-label">Formatted XML</span>
              <div class="ecf-xml-tools">
                <button type="button" data-xml-wrap aria-pressed="true">Wrap lines</button>
                <button type="button" data-copy-xml>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                    <rect x="8" y="8" width="12" height="13" rx="2" /><path d="M16 8V3H3v13h5" />
                  </svg>
                  Copy original
                </button>
              </div>
            </div>
            <pre id="submitted-ecf-xml" class="ecf-xml-code is-wrapped" data-xml-code phx-update="ignore"
              tabindex="0" aria-label="Signed XML document">{@artifact.xml}</pre>
            <div class="ecf-xml-editor-footer">
              <span data-xml-lines>XML</span><span>UTF-8 · Read only</span>
              <span data-xml-status role="status" aria-live="polite"></span>
            </div>
          </div>
          <p class="ecf-xml-caption">Formatting is for reading only. Copy and download preserve the original signed document.</p>
          <details class="ecf-xml-checksum">
            <summary>Document fingerprint <span>SHA-256</span></summary>
            <div><code>{@artifact.sha256}</code><button type="button" data-copy-hash>Copy checksum</button></div>
          </details>
        </div>
      </section>
    </.pos_layout>
    """
  end
end
