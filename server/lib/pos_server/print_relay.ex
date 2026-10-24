defmodule TigooServer.PrintRelay do
  @moduledoc "Tenant-scoped topics and availability lookups for mobile receipt printing."

  alias TigooServerWeb.Presence

  def topic(tenant, store_id), do: "print-relay:#{tenant}:#{store_id}"

  def desktop_topic(tenant, store_id, session_id),
    do: "#{topic(tenant, store_id)}:desktop:#{session_id}"

  def result_topic(tenant, store_id, request_id),
    do: "#{topic(tenant, store_id)}:result:#{request_id}"

  def available_desktops(tenant, store_id) do
    tenant
    |> topic(store_id)
    |> Presence.list()
    |> Enum.flat_map(fn {session_id, %{metas: metas}} ->
      metas
      |> Enum.filter(&(&1.device == "desktop" and &1.printer_online == true))
      |> Enum.map(fn meta ->
        %{
          session_id: session_id,
          label: meta.label || "Desktop",
          printer: meta.printer || "Receipt printer",
          user: meta.user,
          online: true
        }
      end)
    end)
  end

  def available_desktop?(tenant, store_id, session_id) do
    Enum.any?(available_desktops(tenant, store_id), &(&1.session_id == session_id))
  end
end
