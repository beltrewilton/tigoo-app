defmodule TigooServerWeb.Presence do
  use Phoenix.Presence,
    otp_app: :tigoo_server,
    pubsub_server: TigooServer.PubSub
end
