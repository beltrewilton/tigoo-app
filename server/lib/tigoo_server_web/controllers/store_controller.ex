defmodule TigooServerWeb.StoreController do
  use TigooServerWeb, :controller

  alias TigooServer.Retaily.InventoryContext

  def index(conn, _params) do
    {:ok, entries} = InventoryContext.stores(conn.assigns.current_scope)
    json(conn, %{entries: entries})
  end
end
