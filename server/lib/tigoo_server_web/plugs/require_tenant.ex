defmodule TigooServerWeb.Plugs.RequireTenant do
  @moduledoc """
  Rejects tenant-owned API requests without an authenticated tenant scope.
  """

  import Plug.Conn

  alias TigooServer.TenantContext

  def init(opts), do: opts

  def call(conn, _opts) do
    if is_binary(TenantContext.get_tenant()) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(:unauthorized, ~s({"error":"authentication required"}))
      |> halt()
    end
  end
end
