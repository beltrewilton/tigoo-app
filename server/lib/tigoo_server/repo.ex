defmodule TigooServer.Repo do
  use Ecto.Repo,
    otp_app: :tigoo_server,
    adapter: Ecto.Adapters.Postgres
end
