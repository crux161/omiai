import Config

if System.get_env("PHX_SERVER") do
  config :omiai, OmiaiWeb.Endpoint, server: true
end

config :omiai, OmiaiWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

# JWT shared secret for verifying tokens issued by the Python backend
if jwt_secret = System.get_env("OMIAI_JWT_SECRET") do
  config :omiai, :jwt_secret, jwt_secret
end

# Internal API key for webhook auth from Python backend
if internal_key = System.get_env("OMIAI_INTERNAL_API_KEY") do
  config :omiai, :internal_api_key, internal_key
end

# Python backend URL for proxied requests
if backend_url = System.get_env("OMIAI_BACKEND_URL") do
  config :omiai, :backend_url, backend_url
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :omiai, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :omiai, OmiaiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # Require JWT secret in production
  unless Application.get_env(:omiai, :jwt_secret) do
    raise "environment variable OMIAI_JWT_SECRET is missing"
  end
end
