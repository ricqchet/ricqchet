import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :relay, Relay.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "relay_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :relay, RelayWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "cyJYl+w2rLCeP9e1/YjeBBBallS/rwQp7SPt+CgoQZFCIq+39+m0XRsq0I9NdBrd",
  server: false

# Configure Oban for testing
config :relay, Oban, testing: :inline

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
