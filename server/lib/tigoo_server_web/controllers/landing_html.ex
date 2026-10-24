defmodule TigooServerWeb.LandingHTML do
  use TigooServerWeb, :html

  import TigooServerWeb.Landing.Components

  embed_templates "landing_html/*"
end
