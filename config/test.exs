import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

# The periodic bank payer is driven manually in tests
config :tannhauser_gate, :start_payer, false

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :tannhauser_gate, TannhauserGate.Repo,
  username: System.get_env("PGUSER", "postgres"),
  password: System.get_env("PGPASSWORD", "postgres"),
  hostname: System.get_env("PGHOST", "localhost"),
  database: "tannhauser_gate_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tannhauser_gate, TannhauserGateWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "LyrbbDvlnqBrBY7VDv51LHpWvrud0AoJLmLNQCr1eZ2m7QH/o6jc52bQ41eN4cUg",
  server: false

# Email flows are on in tests; flag-off tests override it with Application.put_env/3
config :tannhauser_gate, :feature_email_auth, true

# In test we don't send emails
config :tannhauser_gate, TannhauserGate.Mailer, adapter: Swoosh.Adapters.Test

# Store uploaded avatars in a throwaway directory
config :tannhauser_gate, :uploads_dir, Path.expand("../tmp/test_uploads", __DIR__)

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
