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
  pubsub_server: Omiai.PubSub,
  live_view: [signing_salt: "GJsTIy2oriARVAIE"]

# ICE servers for WebRTC NAT traversal (Google STUN)
config :omiai, :ice_servers, [
  %{urls: "stun:stun.l.google.com:19302"},
  %{urls: "stun:stun1.l.google.com:19302"},
  %{urls: "stun:stun2.l.google.com:19302"},
  %{urls: "stun:stun3.l.google.com:19302"},
  %{urls: "stun:stun4.l.google.com:19302"}
]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
