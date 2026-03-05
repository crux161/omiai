import Config

config :omiai, OmiaiWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "6nbqMM8EPYmOA9ZuhO9J4NBLBm7lEtgAAyFB5CHrOXXSBlWW7x4OdFMpdapYdw/E",
  watchers: []

config :omiai, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime
