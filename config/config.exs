# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ricqchet,
  ecto_repos: [Ricqchet.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :ricqchet, RicqchetWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: RicqchetWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Ricqchet.PubSub,
  live_view: [signing_salt: "1AOKs4fr"]

# Configure Oban for job processing
config :ricqchet, Oban,
  repo: Ricqchet.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Flow control reconciliation - runs every minute
       {"* * * * *", Ricqchet.FlowControl.ReconciliationWorker}
     ]}
  ],
  queues: [delivery: 50, dlq_notifications: 10]

# Batch delivery configuration
config :ricqchet,
  batch_default_max_size: 10,
  batch_default_timeout_seconds: 5,
  batch_dispatcher_enabled: true

# JWT configuration
config :ricqchet,
  jwt_secret: "dev-secret-at-least-32-characters!!",
  jwt_access_token_ttl: 15 * 60,
  jwt_refresh_token_ttl: 7 * 24 * 60 * 60

# CORS configuration
# In production, set CORS_ALLOWED_ORIGINS env var (comma-separated list)
config :ricqchet, :cors,
  allowed_origins: ["http://localhost:3000", "http://localhost:4000"],
  allow_credentials: true,
  max_age: 86_400

# Flop pagination configuration
config :flop,
  repo: Ricqchet.Repo,
  default_limit: 25,
  max_limit: 100,
  pagination_types: [:first, :last, :offset]

# Swoosh mailer configuration
config :ricqchet, Ricqchet.Mailer, adapter: Swoosh.Adapters.Local

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :destination_id, :limit, :delay, :error]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
