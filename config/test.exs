import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :omiai, OmiaiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ZICQsIPLJv4ZmRm7OrFKPYa+0o1B+17C1qM7AhWsh6KXfkgC1Ob/9VVGWaYATuNR",
  server: false

config :omiai, Omiai.Repo,
  pool: Ecto.Adapters.SQL.Sandbox

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
