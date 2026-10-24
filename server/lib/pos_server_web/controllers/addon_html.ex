defmodule TigooServerWeb.AddonHTML do
  use TigooServerWeb, :html

  import TigooServerWeb.PosLayoutComponents

  embed_templates "addon_html/*"
end
