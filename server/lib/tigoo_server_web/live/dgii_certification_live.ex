defmodule TigooServerWeb.DgiiCertificationLive do
  use TigooServerWeb, :live_view
  import TigooServerWeb.PosLayoutComponents
  alias TigooServer.{Authentication, TenantContext}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Fe.{Certification, Credentials, Postulacion}
  alias TigooServer.Retaily.InventoryContext

  def mount(params, session, socket) do
    with token when is_binary(token) <- session["user_token"],
         {:ok, scope} <- Authentication.authenticate(token),
         true <- Scope.allowed?(scope, "company.settings"),
         _ <- TenantContext.put_tenant(scope.tenant),
         {:ok, stores} <- InventoryContext.stores(scope) do
      selected = to_string(params["store_id"] || session["store_id"] || "")
      store = Enum.find(stores, &(to_string(&1.id) == selected)) || List.first(stores)

      {:ok, socket
       |> assign(page_title: "Certificación DGII", scope: scope, stores: stores,
         store_id: store && store.id, token: token, signed: nil, error: nil,
         step: 0, identity_ready: match?({:ok, _}, Credentials.for_tenant(scope.tenant)), identity_error: nil,
         batches: [], batch: nil, batch_id: "", batch_error: nil, submitting: false, submission_status: nil)
       |> load_batches()
       # PKCS#12 extensions are not registered in the default MIME database.
       # Keep the browser filter below; Credentials validates the file on save.
       |> allow_upload(:certificate, auto_upload: true, accept: :any, max_entries: 1, max_file_size: 5_000_000)
       |> allow_upload(:credentials, auto_upload: true, accept: ~w(.txt), max_entries: 1, max_file_size: 64_000)
       |> allow_upload(:xml, auto_upload: true, accept: ~w(.xml), max_entries: 1, max_file_size: 5_000_000)}
    else
      _ -> {:ok, redirect(socket, to: ~p"/pos")}
    end
  end

  def handle_event("change_store", %{"store_id" => id}, socket) do
    case Enum.find(socket.assigns.stores, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      store -> {:noreply, assign(socket, :store_id, store.id)}
    end
  end

  def handle_event("select_step", %{"step" => step}, socket) when step in ["0", "1", "2"],
    do: {:noreply, assign(socket, :step, String.to_integer(step))}

  def handle_event("select_batch", %{"batch_id" => id}, socket) do
    if socket.assigns.submitting do
      {:noreply, socket}
    else
      batch = Enum.find(socket.assigns.batches, &(&1.id == id))
      {:noreply, assign(socket, batch_id: if(batch, do: id, else: ""), batch: batch, submission_status: nil)}
    end
  end

  def handle_event("refresh_batches", _, socket),
    do: {:noreply, load_batches(socket)}

  def handle_event("submit_cases", _, %{assigns: %{submitting: true}} = socket),
    do: {:noreply, socket}

  def handle_event("submit_cases", _, socket) do
    with {:ok, scope} <- Authentication.authenticate(socket.assigns.token),
         true <- scope.tenant == socket.assigns.scope.tenant and Scope.allowed?(scope, "company.settings") do
      id = socket.assigns.batch_id
      socket = load_batches(socket)
      if not is_nil(socket.assigns.batch) and socket.assigns.batch.id == id and is_nil(socket.assigns.batch.journal_error) do
        parent = self()
        {:noreply, socket
         |> assign(submitting: true, submission_status: "Enviando casos a DGII Certificación (CerteCF)…")
         |> start_async(:submit_cases, fn ->
           Certification.submit(scope, id, fn _encf, _state, _body ->
             send(parent, {:certification_progress, id})
           end)
         end)}
      else
        {:noreply, assign(socket, :submission_status, "Selecciona un lote válido de esta empresa antes de enviar.")}
      end
    else
      _ -> {:noreply, redirect(socket, to: ~p"/pos")}
    end
  end

  def handle_event("validate_identity", _, socket),
    do: {:noreply, assign(socket, :identity_error, nil)}

  def handle_event("cancel_identity_upload", %{"kind" => kind, "ref" => ref}, socket)
      when kind in ["certificate", "credentials"] do
    upload = if kind == "certificate", do: :certificate, else: :credentials
    {:noreply, cancel_upload(socket, upload, ref)}
  end

  def handle_event("save_identity", _, socket) do
    with {:ok, scope} <- Authentication.authenticate(socket.assigns.token),
         true <- scope.tenant == socket.assigns.scope.tenant and Scope.allowed?(scope, "company.settings") do
      if upload_ready?(socket.assigns.uploads.certificate) and upload_ready?(socket.assigns.uploads.credentials) do
        [result] = consume_uploaded_entries(socket, :certificate, fn %{path: certificate_path}, certificate ->
          [result] = consume_uploaded_entries(socket, :credentials, fn %{path: credentials_path}, credentials ->
            result = if credentials.client_name == "credentials.txt" do
              Credentials.upload_for_tenant(scope.tenant, certificate_path, certificate.client_name, credentials_path)
            else
              {:error, :invalid_filename}
            end
            {:ok, result}
          end)
          {:ok, result}
        end)

        case result do
          :ok -> {:noreply, assign(socket, identity_ready: true, identity_error: nil, signed: nil, step: 1)}
          _ -> {:noreply, assign(socket, :identity_error,
            "No se pudieron guardar los archivos. Usa un .p12 válido y credentials.txt con una única línea Password: y su contraseña correspondiente. Verifica también los permisos de la carpeta y que no tenga varios certificados .p12.")}
        end
      else
        {:noreply, assign(socket, :identity_error, "Selecciona los dos archivos y espera a que terminen de cargar.")}
      end
    else
      _ -> {:noreply, redirect(socket, to: ~p"/pos")}
    end
  end

  def handle_event("validate", _, socket),
    do: {:noreply, assign(socket, signed: nil, error: nil)}

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :xml, ref)}

  def handle_event("sign", _, socket) do
    with {:ok, scope} <- Authentication.authenticate(socket.assigns.token),
         true <- scope.tenant == socket.assigns.scope.tenant and Scope.allowed?(scope, "company.settings") do
      {complete, pending} = uploaded_entries(socket, :xml)

      if length(complete) == 1 and pending == [] do
        [result] = consume_uploaded_entries(socket, :xml, fn %{path: path}, entry ->
          result = with {:ok, xml} <- File.read(path),
                        {:ok, signed} <- Postulacion.sign(scope.tenant, xml) do
            filename = Path.basename(entry.client_name) |> Path.rootname() |> Kernel.<>(".signed.xml")
            {:ok, %{filename: filename, uri: "data:application/xml;base64," <> Base.encode64(signed)}}
          end
          {:ok, result}
        end)

        case result do
          {:ok, signed} -> {:noreply, assign(socket, signed: signed, error: nil)}
          {:error, :signing_identity_unavailable} ->
            {:noreply, assign(socket, signed: nil, error: "No se encontró un certificado .p12 único y credenciales válidas para esta empresa.")}
          {:error, :invalid_software_version} ->
            {:noreply, assign(socket, signed: nil, error: "VersionSoftware debe ser un número, por ejemplo 1.0. Valores como 1.0.0 no son válidos para DGII. Corrige el XML original y vuelve a cargarlo para firmarlo.")}
          {:error, :invalid_postulacion} ->
            {:noreply, assign(socket, signed: nil, error: "Selecciona un XML válido de DGII con raíz Postulacion (máximo 5 MB).")}
          _ -> {:noreply, assign(socket, signed: nil, error: "No se pudo firmar el XML. Revisa el certificado y la configuración del firmador.")}
        end
      else
        {:noreply, assign(socket, :error, "Selecciona un XML y espera a que termine de cargar.")}
      end
    else
      _ -> {:noreply, redirect(socket, to: ~p"/pos")}
    end
  end

  def handle_info({:certification_progress, id}, socket) do
    if socket.assigns.batch_id == id,
      do: {:noreply, load_batches(socket)}, else: {:noreply, socket}
  end

  def handle_async(:submit_cases, {:ok, :ok}, socket) do
    {:noreply, socket |> assign(submitting: false,
      submission_status: "Todos los casos del lote están aceptados en DGII Certificación.") |> load_batches()}
  end

  def handle_async(:submit_cases, {:ok, {:error, message}}, socket) do
    {:noreply, socket |> assign(submitting: false, submission_status: message) |> load_batches()}
  end

  def handle_async(:submit_cases, {:exit, _}, socket) do
    {:noreply, socket |> assign(submitting: false,
      submission_status: "El envío se interrumpió. Revisa el registro guardado antes de continuar.") |> load_batches()}
  end

  defp load_batches(socket) do
    case Certification.batches(socket.assigns.scope) do
      {:ok, batches} ->
        batch = Enum.find(batches, &(&1.id == socket.assigns.batch_id)) || List.first(batches)
        assign(socket, batches: batches, batch: batch, batch_id: if(batch, do: batch.id, else: ""), batch_error: nil)
      {:error, message} -> assign(socket, batches: [], batch: nil, batch_id: "", batch_error: message)
    end
  end

  defp case_label(state) do
    Map.get(%{"not_sent" => "Sin enviar", "sending" => "Enviando / confirmar recepción",
      "pending" => "Pendiente", "accepted" => "Aceptado", "accepted_conditional" => "Aceptado condicional",
      "rejected" => "Rechazado", "unknown" => "Recepción sin confirmar"}, state, state)
  end

  defp upload_ready?(upload) do
    length(upload.entries) == 1 and upload_errors(upload) == [] and
      Enum.all?(upload.entries, &(&1.done? and upload_errors(upload, &1) == []))
  end

  def render(assigns) do
    ~H"""
    <.pos_layout id="dgii-certification" class="pos-shell invoice-view" active_page={:dgii_certification}
      scope={@scope} stores={@stores} store_id={@store_id}>
      <section class="catalog-panel dgii-certification" aria-labelledby="dgii-title">
        <header>
          <p class="eyebrow">ONBOARDING · CERTIFICACIÓN DGII</p>
          <h1 id="dgii-title">Certificación en 15 pasos</h1>
          <p>Prepara los documentos para el proceso de certificación de tu empresa.</p>
        </header>
        <div class="dgii-wizard">
          <nav aria-label="Pasos de certificación">
            <ol class="dgii-steps">
              <li aria-current={if @step == 0, do: "step"}>
                <button type="button" phx-click="select_step" phx-value-step="0">0. Certificado digital</button>
                <span>{if @identity_ready, do: "Configurado", else: "Requiere configuración"}</span>
              </li>
              <li aria-current={if @step == 1, do: "step"}>
                <button type="button" phx-click="select_step" phx-value-step="1">1. Postulación</button><span>Disponible</span>
              </li>
              <li aria-current={if @step == 2, do: "step"}>
                <button type="button" phx-click="select_step" phx-value-step="2">2. Casos de prueba</button>
                <span>Certificación · CerteCF</span>
              </li>
              <li :for={step <- 3..15} aria-disabled="true"><span>Paso {step}</span><small>Pendiente de habilitar</small></li>
            </ol>
          </nav>
          <section :if={@step == 0} class="dgii-step" aria-labelledby="identity-title">
            <p class="eyebrow">PASO 0 · PREPARACIÓN</p>
            <h2 id="identity-title">Certificado digital</h2>
            <p>Sube el certificado .p12 y el archivo credentials.txt de la empresa <strong>{@scope.tenant}</strong>. Crearemos su carpeta si todavía no existe.</p>
            <p>credentials.txt debe incluir una única línea <code>Password: tu_contraseña</code>.</p>
            <p :if={@identity_ready} class="dgii-notice">Esta empresa ya tiene archivos de firma configurados. Guardar un nuevo par reemplazará los actuales.</p>
            <form id="identity-form" phx-change="validate_identity" phx-submit="save_identity">
              <div :for={{kind, label} <- [{:certificate, "Certificado .p12 (máximo 5 MB)"}, {:credentials, "credentials.txt (máximo 64 KB)"}]}>
                <label for={@uploads[kind].ref}>{label}</label>
                <.live_file_input upload={@uploads[kind]} accept={if kind == :certificate, do: ".p12", else: ".txt"} />
                <div :for={entry <- @uploads[kind].entries} class="dgii-upload">
                  <span>{entry.client_name} · {entry.progress}%</span>
                  <button type="button" phx-click="cancel_identity_upload" phx-value-kind={kind} phx-value-ref={entry.ref}>Quitar</button>
                  <p :for={_error <- upload_errors(@uploads[kind], entry)} role="alert">Revisa el tipo y tamaño del archivo.</p>
                </div>
                <p :for={_error <- upload_errors(@uploads[kind])} role="alert">Selecciona un solo archivo del tipo y tamaño indicados.</p>
              </div>
              <button class="btn" type="submit" phx-disable-with="Guardando…"
                disabled={!upload_ready?(@uploads.certificate) or !upload_ready?(@uploads.credentials)}>
                Guardar y continuar a Postulación
              </button>
            </form>
            <p :if={@identity_error} class="dgii-notice" role="alert">{@identity_error}</p>
            <button :if={@identity_ready} class="btn" type="button" phx-click="select_step" phx-value-step="1">Continuar a Postulación</button>
          </section>
          <section :if={@step == 1} class="dgii-step" aria-labelledby="postulacion-title">
            <p class="eyebrow">PASO 1 DE 15</p>
            <h2 id="postulacion-title">Postulación</h2>
            <p :if={!@identity_ready} class="dgii-notice">Primero configura el certificado y las credenciales en el paso 0.</p>
            <p>Sube el archivo XML de postulación descargado del portal de DGII. Se firmará con el certificado de la empresa <strong>{@scope.tenant}</strong>.</p>
            <p>Utiliza el certificado del representante indicado en la postulación.</p>
            <ol class="dgii-flow" aria-label="Preparación del archivo">
              <li>Cargar XML</li><li>Firmar</li><li>Descargar y enviar a DGII</li>
            </ol>
            <form id="postulacion-form" phx-change="validate" phx-submit="sign">
              <label for={@uploads.xml.ref}>Archivo XML de postulación (máximo 5 MB)</label>
              <.live_file_input upload={@uploads.xml} />
              <div :for={entry <- @uploads.xml.entries} class="dgii-upload">
                <span>{entry.client_name} · {entry.progress}%</span>
                <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref}>Quitar</button>
                <p :for={_error <- upload_errors(@uploads.xml, entry)} role="alert">El archivo debe ser un XML de máximo 5 MB.</p>
              </div>
              <p :for={_error <- upload_errors(@uploads.xml)} role="alert">Selecciona un solo archivo XML de máximo 5 MB.</p>
              <button class="btn" type="submit" phx-disable-with="Firmando…"
                disabled={!@identity_ready or @uploads.xml.entries == [] or Enum.any?(@uploads.xml.entries, &(!&1.done?)) or upload_errors(@uploads.xml) != []}>
                Firmar XML
              </button>
            </form>
            <p :if={@error} class="dgii-notice" role="alert">{@error}</p>
            <div :if={@signed} class="dgii-notice" role="status">
              <h3>XML firmado y listo para descargar</h3>
              <a class="btn" href={@signed.uri} download={@signed.filename}>Descargar {@signed.filename}</a>
              <p>En el portal de DGII, carga este archivo en «Envío de archivo de postulación firmado». No modifiques el XML después de firmarlo.</p>
              <p>La firma no confirma la aprobación de DGII. El archivo estará disponible mientras permanezcas en esta página.</p>
            </div>
            <button class="btn" type="button" phx-click="select_step" phx-value-step="2">Continuar a casos de prueba</button>
          </section>
          <section :if={@step == 2} class="dgii-step" aria-labelledby="cases-title" aria-busy={@submitting}>
            <p class="eyebrow">PASO 2 DE 15 · CERTECF</p>
            <h2 id="cases-title">Enviar casos de prueba</h2>
            <p>Envía los XML firmados del lote generado para esta empresa a <strong>DGII Certificación (CerteCF)</strong>.</p>
            <form id="certification-batch-form" phx-change="select_batch">
              <label for="certification-batch">Lote de casos firmados</label>
              <select id="certification-batch" name="batch_id" disabled={@submitting or @batches == []}>
                <option :if={@batches == []} value="">No hay lotes disponibles</option>
                <option :for={batch <- @batches} value={batch.id} selected={batch.id == @batch_id}>
                  {batch.id} · RNC {batch.issuer} · {batch.count} casos
                </option>
              </select>
            </form>
            <button class="btn" type="button" phx-click="refresh_batches" disabled={@submitting}>Actualizar resultados</button>
            <p :if={@batch_error} class="dgii-notice" role="alert">{@batch_error}</p>
            <p :if={!@batch and !@batch_error} class="dgii-notice">No hay lotes ECF generados para el RNC de esta empresa en la carpeta de certificación.</p>
            <div :if={@batch}>
              <p><strong>{@batch.accepted} de {@batch.count}</strong> casos aceptados · RNC {@batch.issuer}</p>
              <progress value={@batch.accepted} max={@batch.count} aria-label="Casos aceptados"></progress>
              <p>Los casos aceptados se omiten. Los pendientes con Track ID se consultan sin volver a enviarlos. Los casos rechazados o sin recepción confirmada requieren revisión.</p>
              <p :if={@batch.portal_count > 0}>Este lote incluye {@batch.portal_count} casos de consumo menor a RD$250,000: se envían sus resúmenes RFCE; los ECF completos se cargan manualmente en el portal, igual que en el proceso existente.</p>
              <p :if={@batch.journal_error} class="dgii-notice" role="alert">{@batch.journal_error}</p>
              <button class="btn" type="button" phx-click="submit_cases"
                disabled={@submitting or !@identity_ready or not is_nil(@batch.journal_error) or @batch.accepted == @batch.count}>
                {if @submitting, do: "Enviando…", else: "Enviar / continuar casos en CerteCF"}
              </button>
              <p :if={!@identity_ready}>Configura el certificado de esta empresa en el paso 0.</p>
              <p :if={@batch.last_error} class="dgii-notice" role="alert">Último resultado del envío: {@batch.last_error}</p>
              <div class="dgii-cases-table">
                <table>
                  <caption>Resultados de los casos de prueba</caption>
                  <thead><tr><th scope="col">eNCF</th><th scope="col">Canal</th><th scope="col">Monto RD$</th><th scope="col">Estado</th><th scope="col">Detalle DGII</th></tr></thead>
                  <tbody>
                    <tr :for={row <- @batch.rows}>
                      <td>{row.encf}</td><td>{row.channel}</td><td>{row.amount}</td><td>{case_label(row.state)}</td>
                      <td>
                        <span :if={row.track_id}>Track ID: {row.track_id}</span>
                        <details :if={row.response}><summary>Ver respuesta</summary><pre>{Jason.encode!(row.response, pretty: true)}</pre></details>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
            <p :if={@submission_status} class="dgii-notice" role="status" aria-live="polite">{@submission_status}</p>
          </section>
        </div>
      </section>
    </.pos_layout>
    """
  end
end
