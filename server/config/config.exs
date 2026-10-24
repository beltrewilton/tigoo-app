# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :tigoo_server,
  ecto_repos: [TigooServer.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :triplex,
  repo: TigooServer.Repo,
  reserved_tenants: ~w(www api admin app mail support status assets static docs auth login signup billing)

# Configures the endpoint
config :tigoo_server, TigooServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TigooServerWeb.ErrorHTML, json: TigooServerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TigooServer.PubSub,
  live_view: [signing_salt: "4nSOswhS"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :tigoo_server, TigooServer.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :esbuild,
  version: "0.25.4",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{
      "NODE_PATH" =>
        [
          Path.expand("../deps", __DIR__),
          Mix.Project.build_path()
        ]
    }
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
