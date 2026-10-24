defmodule TigooServerWeb.LandingController do
  use TigooServerWeb, :controller

  alias TigooServer.Accounts

  def index(conn, _params) do
    current_user =
      case conn.assigns[:current_scope] do
        %{actor: :admin, actor_id: user_id} -> Accounts.get_user(user_id)
        _ -> nil
      end

    conn
    |> put_root_layout(html: {TigooServerWeb.LandingLayouts, :root})
    |> render(:index,
      current_user: current_user,
      profile_url: profile_url(current_user),
      page_title: "tigoo",
      page_description:
        "Ventas, inventario y facturación electrónica para negocios que quieren avanzar.",
      canonical_path: "/"
    )
  end

  def privacy_policy(conn, _params) do
    render_legal_page(conn, :privacy_policy,
      page_title: "Política de privacidad | tigoo",
      page_description: "Conoce cómo tigoo recopila, usa y protege tu información.",
      canonical_path: "/privacy-policy"
    )
  end

  def terms_of_service(conn, _params) do
    render_legal_page(conn, :terms_of_service,
      page_title: "Términos de servicio | tigoo",
      page_description: "Lee los términos que rigen el uso de tigoo.",
      canonical_path: "/terms-of-service"
    )
  end

  def not_found(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:not_found, TigooServerWeb.ErrorHTML.not_found_page())
  end

  defp render_legal_page(conn, template, assigns) do
    conn
    |> put_root_layout(html: {TigooServerWeb.LandingLayouts, :root})
    |> render(template, assigns)
  end

  defp profile_url(%{tenant: tenant}) when is_binary(tenant) and tenant != "" do
    url = TigooServerWeb.Endpoint.config(:url)
    host = url |> Keyword.get(:host, "localhost") |> to_string()
    scheme = url |> Keyword.get(:scheme, "https") |> to_string()

    URI.to_string(%URI{scheme: scheme, host: "#{tenant}.#{host}", path: ~p"/pos/dashboard"})
  end

  defp profile_url(_current_user), do: ~p"/pos/dashboard"
end
