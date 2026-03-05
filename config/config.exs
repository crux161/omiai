import Config

config :omiai,
  generators: [timestamp_type: :utc_datetime, binary_id: true]

config :omiai, OmiaiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: OmiaiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Omiai.PubSub

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
