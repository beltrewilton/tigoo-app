defmodule TigooServer.Addons.Events do
  @moduledoc false

  require Logger

  alias TigooServer.Addons
  alias TigooServer.Addons.Installer
  alias TigooServer.Repo
  alias TigooServer.TenantContext

  @event_callbacks %{
    sale_completed: {:on_sale_completed, 2}
  }

  def dispatch(event, payload, scope) do
    with {:ok, event_name} <- normalize_event(event),
         tenant when is_binary(tenant) and tenant != "" <- Map.get(scope, :tenant) do
      addons = Addons.enabled_for_event(tenant, event_name)

      if addons != [] do
        dispatch_async(event_name, payload, scope, addons)
      end
    else
      _ -> :ok
    end

    :ok
  end

  defp dispatch_async(event_name, payload, scope, addons) do
    try do
      Task.Supervisor.start_child(TigooServer.TaskSupervisor, fn ->
        TenantContext.put_tenant(scope.tenant)

        Enum.each(addons, fn addon ->
          invoke_addon(addon, event_name, payload, event_context(addon, event_name, payload, scope))
        end)
      end)
      |> case do
        {:ok, _pid} -> :ok
        {:error, reason} -> Logger.error("addon_event_dispatch_failed: #{inspect(reason)}")
      end
    rescue
      error -> Logger.error("addon_event_dispatch_crashed: #{Exception.message(error)}")
    end
  end

  defp invoke_addon(addon, event_name, payload, context) do
    with {:ok, {callback, arity}} <- callback_for(event_name),
         {:ok, handler} <- Installer.handler(addon),
         true <- function_exported?(handler, callback, arity) do
      apply_callback(handler, callback, payload, context, addon, event_name)
    else
      false ->
        Logger.warning(
          "addon_event_callback_missing: addon=#{addon.identifier} event=#{event_name}"
        )

      {:error, reason} ->
        Logger.error(
          "addon_event_callback_unavailable: addon=#{addon.identifier} event=#{event_name} reason=#{inspect(reason)}"
        )
    end
  end

  defp apply_callback(handler, callback, payload, context, addon, event_name) do
    try do
      case apply(handler, callback, [payload, context]) do
        :ok ->
          :ok

        {:ok, _result} ->
          :ok

        other ->
          Logger.warning(
            "addon_event_callback_returned: addon=#{addon.identifier} event=#{event_name} result=#{inspect(other)}"
          )
      end
    rescue
      error ->
        Logger.error(
          "addon_event_callback_failed: addon=#{addon.identifier} event=#{event_name} sale_id=#{sale_id(payload)} reason=#{Exception.message(error)}"
        )
    catch
      kind, reason ->
        Logger.error(
          "addon_event_callback_threw: addon=#{addon.identifier} event=#{event_name} kind=#{inspect(kind)} reason=#{inspect(reason)}"
        )
    end
  end

  defp event_context(addon, event_name, payload, scope) do
    %{
      event: %{
        name: event_name,
        occurred_at: DateTime.utc_now() |> DateTime.truncate(:second)
      },
      addon: %{identifier: addon.identifier, route: "/pos/addons/#{addon.identifier}"},
      tenant: scope.tenant,
      actor: %{
        id: Map.get(scope, :actor_id),
        type: Map.get(scope, :actor),
        login: Map.get(scope, :login)
      },
      store: %{id: store_id(payload)},
      host: %{app: :pos, boundary: :event_callback},
      params: %{source: :checkout},
      repo: Repo
    }
  end

  defp normalize_event(event) when is_atom(event), do: normalize_event(Atom.to_string(event))

  defp normalize_event("sale_completed"), do: {:ok, :sale_completed}

  defp normalize_event(_event), do: {:error, :unsupported_event}

  defp callback_for(event_name) do
    case Map.fetch(@event_callbacks, event_name) do
      {:ok, callback} -> {:ok, callback}
      :error -> {:error, :unsupported_event}
    end
  end

  defp sale_id(%{id: id}), do: id
  defp sale_id(%{"id" => id}), do: id
  defp sale_id(_payload), do: nil

  defp store_id(%{store_id: store_id}), do: store_id
  defp store_id(%{"store_id" => store_id}), do: store_id
  defp store_id(_payload), do: nil
end
