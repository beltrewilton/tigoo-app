defmodule TigooServerWeb.DgiiCertificationController do
  use TigooServerWeb, :controller
  alias TigooServer.Authentication
  alias TigooServer.Fe.Certification

  def download(conn, %{"batch" => batch, "encf" => encf}) do
    with token when is_binary(token) <- get_session(conn, "user_token"),
         {:ok, scope} <- Authentication.authenticate(token),
         {:ok, artifact} <- Certification.portal_document(scope, batch, encf) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> send_download({:binary, artifact.xml}, filename: artifact.filename, content_type: "application/xml")
    else
      _ -> conn |> put_status(:not_found) |> text("El XML firmado no está disponible para esta empresa.")
    end
  end
end
