import Config

config :omiai, OmiaiWeb.Endpoint,
  # Bind on all interfaces so iOS/LAN devices can reach this node directly.
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "6nbqMM8EPYmOA9ZuhO9J4NBLBm7lEtgAAyFB5CHrOXXSBlWW7x4OdFMpdapYdw/E",
  watchers: []

config :omiai, dev_routes: true

config :omiai, Omiai.Repo,
  journal_mode: :wal,
  cache_size: -64000

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime
