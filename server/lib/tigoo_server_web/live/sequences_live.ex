defmodule TigooServerWeb.SequencesLive do
  @moduledoc false
  use TigooServerWeb, :live_view
  import TigooServerWeb.PosLayoutComponents

  alias TigooServer.{Authentication, TenantContext}
  alias TigooServer.Accounts.Scope
  alias TigooServer.Retaily.{InventoryContext, SequenceSettings}

  @kinds ~w(standard rotation)

  @impl true
  def mount(params, session, socket) do
    with token when is_binary(token) <- session["user_token"],
         {:ok, scope} <- Authentication.authenticate(token),
         true <- Scope.allowed?(scope, "company.settings"),
         _ <- TenantContext.put_tenant(scope.tenant),
         {:ok, stores} <- InventoryContext.stores(scope) do
      selected = to_string(params["store_id"] || session["store_id"] || "")
      store = Enum.find(stores, &(to_string(&1.id) == selected)) || List.first(stores)

      {:ok, socket
       |> assign(page_title: "Tigoo Sequences", scope: scope, stores: stores,
         store_id: store && store.id, editing: nil, form: nil, status: "")
       |> reload()}
    else
      _ -> {:ok, socket |> put_flash(:error, "Company settings access is required.") |> redirect(to: ~p"/pos")}
    end
  end

  @impl true
  def handle_event("change_store", %{"store_id" => id}, socket) do
    case Enum.find(socket.assigns.stores, &(to_string(&1.id) == id)) do
      nil -> {:noreply, socket}
      store -> {:noreply, assign(socket, :store_id, store.id)}
    end
  end

  def handle_event("add", %{"kind" => kind}, socket) when kind in @kinds do
    record = SequenceSettings.new(kind)
    {:noreply, edit(socket, kind, record)}
  end

  def handle_event("edit", %{"kind" => kind, "id" => id}, socket) when kind in @kinds do
    case Enum.find(entries(socket.assigns.sequences, kind), &(to_string(&1.id) == id)) do
      nil -> {:noreply, assign(socket, :status, "This item could not be found.")}
      record -> {:noreply, edit(socket, kind, record)}
    end
  end

  def handle_event("cancel", _, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil, status: "")}

  def handle_event("validate", %{"sequence" => attrs}, %{assigns: %{editing: {kind, record}}} = socket) do
    changeset = SequenceSettings.change(kind, record, attrs) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :sequence))}
  end

  def handle_event("save", %{"sequence" => attrs}, %{assigns: %{editing: {kind, record}}} = socket) do
    # Re-read and lock on save so generator updates cannot be overwritten by
    # the record captured when this form was opened.
    case SequenceSettings.save(kind, record.id, attrs) do
      {:ok, _} -> {:noreply, socket |> assign(editing: nil, form: nil, status: "") |> reload()}
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, editing: {kind, changeset.data},
          form: to_form(changeset, as: :sequence))}
      {:error, _} -> {:noreply, assign(socket, :status, "Could not save sequence.")}
    end
  rescue
    _error in [Postgrex.Error, Ecto.ConstraintError, DBConnection.ConnectionError] ->
      {:noreply, assign(socket, :status, "Could not save sequence.")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id),
         {:ok, _} <- SequenceSettings.delete_standard(id) do
      {:noreply, socket |> assign(editing: nil, form: nil, status: "") |> reload()}
    else
      _ -> {:noreply, assign(socket, :status, "Could not delete sequence.")}
    end
  rescue
    _error in [Postgrex.Error, Ecto.ConstraintError, DBConnection.ConnectionError] ->
      {:noreply, assign(socket, :status, "Could not delete sequence.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.pos_layout id="sequences-live" class="pos-shell invoice-view" active_page={:sequences}
      scope={@scope} stores={@stores} store_id={@store_id}
      phx-hook="Sequences" data-editing={editing_key(@editing)}>
      <section class="catalog-panel" data-view="company-settings" aria-labelledby="sequences-title">
        <section class="company-settings-screen" id="sequences-screen" aria-labelledby="sequences-title">
          <div class="company-settings-fixed">
            <header class="topbar company-settings-topbar">
              <div class="brand-lockup">
                <span class="brand-mark" aria-hidden="true">E</span>
                <div>
                  <p class="eyebrow" data-i18n="company.company">Company</p>
                  <h2 id="sequences-title" tabindex="-1" data-i18n="sequences.title">Sequences</h2>
                </div>
              </div>
              <a class="btn" data-variant="outline" href={~p"/pos/company-settings?store_id=#{@store_id}"}>
                <span data-i18n="company.title">Company settings</span>
              </a>
            </header>
            <p class="company-settings-status" role="status" data-i18n={status_key(@status)}>{@status}</p>
          </div>
          <div class="company-settings-cards">
            <article :for={kind <- ["standard", "rotation"]} class="card company-settings-card"
              aria-labelledby={"#{kind}-sequences-title"}>
              <div class="card-header company-settings-card-header">
                <div>
                  <h3 id={"#{kind}-sequences-title"} class="card-title" data-i18n={"sequences.#{kind}"}>
                    {if kind == "standard", do: "Sales sequences", else: "Monthly rotating sequences"}
                  </h3>
                  <p class="card-description" data-i18n={"sequences.#{kind}Copy"}>
                    {if kind == "standard", do: "Configure invoice numbers for CF, VF and DV sales.",
                      else: "Configure a monthly window with cyclic number reuse."}
                  </p>
                </div>
                <button class="btn" data-variant="default" data-size="sm" type="button"
                  phx-click="add" phx-value-kind={kind}>
                  <span data-i18n="company.addSequence">Add sequence</span>
                </button>
              </div>
              <div class="card-content">
                <.sequence_form :if={editing_kind(@editing) == kind} form={@form}
                  kind={kind} record={elem(@editing, 1)} />
                <p :if={entries(@sequences, kind) == []} class="field-description company-settings-empty"
                  data-i18n="sequences.empty">No sequences configured.</p>
                <div :for={record <- entries(@sequences, kind)} class="company-setting-row">
                  <div>
                    <strong>{record.code} · {record.name}</strong>
                    <p class="field-description">
                      <span data-i18n="company.prefix">Prefix</span>: {record.prefix} ·
                      <span data-i18n="sequences.base">Current base</span>: {record.current_seq}
                    </p>
                    <p :if={kind == "standard"} class="field-description">
                      <span data-i18n="company.digits">Digits</span>: {record.fill} ·
                      <span data-i18n="company.increment">Increment</span>: {record.increment_by}
                    </p>
                    <p :if={kind == "rotation"} class="field-description">
                      <span data-i18n="sequences.windowSize">Window size</span>: {display(record.rotation_available)} ·
                      <span data-i18n="sequences.allowedSteps">Allowed steps</span>: {display(record.rotation_allowed_steps)}
                    </p>
                    <p :if={kind == "rotation"} class="field-description">
                      <span data-i18n="sequences.period">Month</span>: {record.period || "—"} ·
                      <span data-i18n="sequences.step">Step</span>: {display(record.rotation_step)} ·
                      <span data-i18n="sequences.lastNumber">Last number</span>: {record.current_seq_rotation || "—"}
                    </p>
                  </div>
                  <div class="company-setting-actions">
                    <button class="btn" data-variant="outline" data-size="sm" type="button"
                      phx-click="edit" phx-value-kind={kind} phx-value-id={record.id}>
                      <span data-i18n="common.edit">Edit</span>
                    </button>
                    <button :if={kind == "standard"} class="btn" data-variant="destructive" data-size="sm"
                      type="button" phx-click="delete" phx-value-id={record.id} data-confirm="Delete this sequence set?">
                      <span data-i18n="common.delete">Delete</span>
                    </button>
                  </div>
                </div>
              </div>
            </article>
          </div>
        </section>
      </section>
    </.pos_layout>
    """
  end

  attr :form, :any, required: true
  attr :kind, :string, required: true
  attr :record, :any, required: true
  defp sequence_form(assigns) do
    assigns = assign(assigns, :fields, fields(assigns.kind))
    ~H"""
    <.form for={@form} id="sequence-settings-form" class="form company-setting-form"
      phx-change="validate" phx-submit="save">
      <p :if={@kind == "rotation"} class="field-description" data-i18n="sequences.rotationHelp">
        Counts are calculated automatically. Active-month configuration and an initialized base cannot be edited.
      </p>
      <div :for={{name, label, key, type} <- @fields} class="form-field">
        <label class="label" for={@form[name].id} data-i18n={key}>{label}</label>
        <input class="input" id={@form[name].id} name={@form[name].name} value={display_input(@form[name].value)}
          type={type} step={if type == "number", do: if(name in amount_fields(), do: "any", else: "1")}
          min={if type == "number", do: if(name == :current_seq or name in amount_fields(), do: "0", else: "1")}
          required disabled={@kind == "rotation" and name == :current_seq and not is_nil(@record.rotation_window_start)}
          aria-invalid={if @form[name].errors != [], do: "true"}
          aria-describedby={if @form[name].errors != [], do: "#{@form[name].id}-errors"} />
        <div :if={@form[name].errors != []} id={"#{@form[name].id}-errors"} class="sequence-field-errors" role="alert">
          <p :for={error <- @form[name].errors} class="field-description">{error_text(error)}</p>
        </div>
      </div>
      <div class="form-actions">
        <button class="btn" type="button" data-variant="outline" phx-click="cancel">
          <span data-i18n="common.cancel">Cancel</span>
        </button>
        <button class="btn" type="submit" data-variant="default" phx-disable-with="…">
          <span data-i18n="common.save">Save</span>
        </button>
      </div>
    </.form>
    """
  end

  defp edit(socket, kind, record) do
    assign(socket, editing: {kind, record}, status: "",
      form: to_form(SequenceSettings.change(kind, record, %{}), as: :sequence))
  end

  defp reload(socket) do
    assign(socket, :sequences, SequenceSettings.list())
  rescue
    _error in [Postgrex.Error, DBConnection.ConnectionError] ->
      assign(socket, sequences: %{standard: [], rotation: []}, status: "Sequences could not be loaded.")
  end

  defp status_key("Sequences could not be loaded."), do: "sequences.loadFailed"
  defp status_key("Could not save sequence."), do: "sequences.saveFailed"
  defp status_key("Could not delete sequence."), do: "sequences.deleteFailed"
  defp status_key("This item could not be found."), do: "company.notFound"
  defp status_key(_), do: nil
  defp editing_key(nil), do: ""
  defp editing_key({kind, record}), do: "#{kind}:#{record.id || "new"}"
  defp editing_kind(nil), do: nil
  defp editing_kind({kind, _}), do: kind
  defp entries(sequences, "standard"), do: sequences.standard
  defp entries(sequences, "rotation"), do: sequences.rotation
  defp amount_fields, do: [:consumer_estatimation_monthly_amount, :consumer_allowed_monthly_amount, :consumer_avg]

  defp fields(kind) do
    common = [
      {:name, "Name", "common.name", "text"},
      {:code, "Code", "common.code", "text"},
      {:prefix, "Prefix", "company.prefix", "text"},
      {:fill, "Digits", "company.digits", "number"},
      {:current_seq, "Current base", "sequences.base", "number"}
    ]
    if kind == "standard" do
      common ++ [{:increment_by, "Increment", "company.increment", "number"}]
    else
      common ++ [
        {:consumer_estatimation_monthly_amount, "Estimated monthly amount", "sequences.estimated", "number"},
        {:consumer_allowed_monthly_amount, "Allowed monthly amount", "sequences.allowed", "number"},
        {:consumer_avg, "Average amount", "sequences.average", "number"}
      ]
    end
  end

  defp display(nil), do: "—"
  defp display(value), do: to_string(value)
  defp display_input(nil), do: nil
  defp display_input(value), do: to_string(value)

  defp error_text({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, text -> String.replace(text, "%{#{key}}", to_string(value)) end)
  end
end
