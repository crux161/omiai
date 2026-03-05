defmodule OmiaiWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :omiai

  socket "/ws/sankaku", OmiaiWeb.SankakuSocket,
    websocket: [
      connect_info: [peer_data: true, x_headers: ["user-agent"], uri: true]
    ]

  plug Plug.Static,
    at: "/",
    from: :omiai,
    gzip: not code_reloading?,
    only: OmiaiWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug OmiaiWeb.Plugs.SankakuHandshakeAuth

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.Head
  plug :health_endpoint
  plug OmiaiWeb.Router

  defp health_endpoint(%Plug.Conn{request_path: "/health", method: "GET"} = conn, _opts) do
    payload = %{
      status: "ok",
      service: "omiai",
      ts: System.system_time(:millisecond)
    }

    body = Jason.encode!(payload)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, body)
    |> Plug.Conn.halt()
  end

  defp health_endpoint(conn, _opts), do: conn
end
