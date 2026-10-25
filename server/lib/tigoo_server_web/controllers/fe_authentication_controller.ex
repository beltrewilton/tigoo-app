defmodule TigooServerWeb.FeAuthenticationController do
  use TigooServerWeb, :controller

  import Saxy.XML, only: [element: 3]

  alias TigooServer.FeAuthentication

  def semilla(conn, _params) do
    seed = FeAuthentication.new_seed()

    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")
      |> put_resp_header("vary", "Accept")

    case get_format(conn) do
      "json" -> json(conn, seed)
      "xml" -> xml(conn, seed)
    end
  end

  defp xml(conn, seed) do
    document =
      element("SemillaModel", [], [
        element("valor", [], seed.valor),
        element("fecha", [], seed.fecha),
        # The supplied XSD requires one extension element after fecha.
        # Version is application metadata, not a digital signature.
        element("version", [], seed.version)
      ])

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(:ok, Saxy.encode!(document, version: "1.0", encoding: "UTF-8"))
  end
end
