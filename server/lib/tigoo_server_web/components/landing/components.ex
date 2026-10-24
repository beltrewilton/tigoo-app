defmodule TigooServerWeb.Landing.Components do
  @moduledoc """
  Page-local building blocks for the root landing page.

  The static source has bespoke SVG-heavy section markup, so it remains in the
  HEEx template to preserve the supplied design exactly. These components are
  intentionally local to the landing page.
  """
  use Phoenix.Component

  slot :inner_block, required: true

  def page_shell(assigns) do
    ~H"""
    <div class="landing-page" data-landing-page>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :rest, :global
  slot :inner_block, required: true

  def navbar(assigns) do
    ~H"""
    <nav {@rest}>{render_slot(@inner_block)}</nav>
    """
  end

  attr :rest, :global
  slot :inner_block, required: true

  def section(assigns) do
    ~H"""
    <section {@rest}>{render_slot(@inner_block)}</section>
    """
  end

  attr :rest, :global
  slot :inner_block, required: true

  def footer(assigns) do
    ~H"""
    <footer {@rest}>{render_slot(@inner_block)}</footer>
    """
  end

  attr :class, :string, default: "section-title"
  slot :inner_block, required: true

  def section_heading(assigns) do
    ~H"""
    <h2 class={@class}>{render_slot(@inner_block)}</h2>
    """
  end
end
