defmodule TigooServerWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use TigooServerWeb, :html

  def not_found_page do
    error_page(
      "404",
      "Page not found",
      "The page you requested does not exist or may have moved.",
      ~s(<a class="btn" data-variant="default" href="/">Go Home</a><a class="btn" data-variant="outline" href="/pos/login">Sign In</a>)
    )
  end

  def internal_server_error_page do
    error_page(
      "500",
      "Internal server error",
      "Something went wrong while processing this request. Please try again in a moment.",
      ~s(<a class="btn" data-variant="default" href="/">Go Home</a>),
      "danger"
    )
  end

  def tenant_required_page(message) do
    error_page(
      "404",
      "Organization address required",
      message,
      ~s(<a class="btn" data-variant="default" href="/">Go Home</a>)
    )
  end

  def render(:"404", assigns), do: render("404.html", assigns)
  def render("404", assigns), do: render("404.html", assigns)
  def render(:"404.html", assigns), do: render("404.html", assigns)

  def render("404.html", _assigns), do: not_found_page()

  def render(:"500", assigns), do: render("500.html", assigns)
  def render("500", assigns), do: render("500.html", assigns)
  def render(:"500.html", assigns), do: render("500.html", assigns)

  def render("500.html", _assigns), do: internal_server_error_page()

  def render(:"tenant_required.html", assigns), do: render("tenant_required.html", assigns)

  def render("tenant_required.html", assigns) do
    message =
      Map.get(assigns, :message) ||
        "This page requires your organization's unique web address. Please contact your administrator for the correct link."

    tenant_required_page(message)
  end

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  defp error_page(status, title, message, actions, tone \\ "neutral") do
    """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{escape(status)} | tigoo</title>
        <link rel="icon" type="image/x-icon" href="/favicon.ico">
        <link rel="stylesheet" href="/assets/ui/default-semantic-tokens.css">
        <link rel="stylesheet" href="/assets/ui/fonts/inter.css">
        <link rel="stylesheet" href="/assets/ui/components/typography/typography.css">
        <link rel="stylesheet" href="/assets/ui/components/button/button.css">
        <link rel="stylesheet" href="/assets/ui/components/card/card.css">
        <link rel="stylesheet" href="/assets/ui/components/alert/alert.css">
        <style>
          *, *::before, *::after { box-sizing: border-box; }
          html { min-height: 100%; background: var(--background); color: var(--foreground); font-family: var(--font-sans); }
          body { min-height: 100dvh; margin: 0; background: var(--background); }
          .error-page { min-height: 100dvh; display: grid; place-items: center; padding: 1.5rem; }
          .error-card { width: min(100%, 31rem); border-radius: var(--radius-lg); box-shadow: var(--shadow-lg); }
          .error-card .card-header { gap: 0.75rem; padding: 1.75rem 1.75rem 0; }
          .error-status { width: fit-content; border: 1px solid var(--border); border-radius: var(--radius-md); padding: 0.25rem 0.5rem; background: var(--muted); color: var(--muted-foreground); font-family: var(--font-mono); font-size: 0.8125rem; font-weight: 600; line-height: 1; }
          .error-card .card-title { font-size: clamp(1.5rem, 4vw, 2rem); letter-spacing: 0; }
          .error-card .card-content { display: grid; gap: 1.25rem; padding: 1.25rem 1.75rem 1.75rem; }
          .error-alert { background: var(--secondary); }
          .error-card[data-tone="danger"] .error-status { border-color: color-mix(in oklch, var(--destructive) 45%, var(--border)); background: color-mix(in oklch, var(--destructive) 10%, var(--background)); color: var(--destructive); }
          .error-actions { display: flex; flex-wrap: wrap; gap: 0.75rem; }
          @media (max-width: 420px) {
            .error-page { padding: 1rem; }
            .error-card .card-header { padding: 1.25rem 1.25rem 0; }
            .error-card .card-content { padding: 1rem 1.25rem 1.25rem; }
            .error-actions { flex-direction: column; }
            .error-actions .btn { width: 100%; }
          }
        </style>
      </head>
      <body>
        <main class="error-page">
          <section class="card error-card" data-tone="#{escape(tone)}" aria-labelledby="error-title">
            <div class="card-header">
              <span class="error-status">#{escape(status)}</span>
              <h1 id="error-title" class="card-title">#{escape(title)}</h1>
              <p class="card-description">#{escape(message)}</p>
            </div>
            <div class="card-content">
              <div class="alert error-alert" role="status">
                <div class="alert-content">
                  <p class="alert-title">Request unavailable</p>
                  <p class="alert-description">No tenant or account details were exposed in this response.</p>
                </div>
              </div>
              <div class="error-actions">#{actions}</div>
            </div>
          </section>
        </main>
      </body>
    </html>
    """
  end

  defp escape(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
