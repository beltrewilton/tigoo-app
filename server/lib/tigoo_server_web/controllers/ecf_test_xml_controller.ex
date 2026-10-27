defmodule TigooServerWeb.EcfTestXmlController do
  use TigooServerWeb, :controller
  alias TigooServer.Authentication
  alias TigooServer.Fe.TestInvoices

  def verify(conn, %{"id" => id}) do
    with token when is_binary(token) <- get_session(conn, "user_token"),
         {:ok, scope} <- Authentication.authenticate(token),
         true <- TestInvoices.enabled?(scope),
         {:ok, verification} <- TestInvoices.verification_url(scope, id) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> redirect(external: verification.url)
    else
      _ -> conn |> put_status(:not_found) |> text("Signed invoice is unavailable for DGII verification.")
    end
  end

  def download(conn, %{"id" => id}) do
    with token when is_binary(token) <- get_session(conn, "user_token"),
         {:ok, scope} <- Authentication.authenticate(token),
         true <- TestInvoices.enabled?(scope),
         {:ok, artifact} <- TestInvoices.posted_xml(scope, id) do
      conn
      |> put_resp_header("cache-control", "no-store")
      |> send_download({:binary, artifact.xml}, filename: artifact.filename, content_type: "application/xml")
    else
      _ -> conn |> put_status(:not_found) |> text("Submitted XML is unavailable.")
    end
  end
end
