defmodule TigooServerWeb.LiveViewAssetController do
  use TigooServerWeb, :controller

  # Serve the browser client supplied by the installed Phoenix LiveView
  # dependency. This keeps the JavaScript protocol version identical to the
  # server without requiring an asset compilation step.
  def show(conn, _params) do
    path = Application.app_dir(:phoenix_live_view, "priv/static/phoenix_live_view.esm.js")

    conn
    |> put_resp_content_type("text/javascript")
    |> put_resp_header("cache-control", "public, max-age=0, must-revalidate")
    |> send_file(200, path)
  end

  # The POS stylesheet is deliberately served verbatim from the desktop
  # client's source of truth. The server-side HEEx uses the same class names,
  # so no parallel, approximate CSS implementation can drift from Tauri.
  def pos_css(conn, _params) do
    path = Path.expand("../../../../client/src/css/app.css", __DIR__)

    conn
    |> put_resp_content_type("text/css")
    |> put_resp_header("cache-control", "no-cache")
    |> send_file(200, path)
  end

  def login_css(conn, _params) do
    path = Path.expand("../../../../client/src/css/login.css", __DIR__)

    conn
    |> put_resp_content_type("text/css")
    |> put_resp_header("cache-control", "no-cache")
    |> send_file(200, path)
  end
end
