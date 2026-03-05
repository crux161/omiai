defmodule OmiaiWeb.Plugs.SankakuHandshakeAuth do
  @moduledoc """
  Pre-validates websocket handshake shape for Sankaku signaling connections.

  This plug intentionally performs only structural checks via SocketAuth and
  does not enforce cryptographic signature ownership yet.
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  alias OmiaiWeb.Auth.SocketAuth

  @ws_path_prefix "/ws/sankaku"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if signaling_ws_request?(conn) do
      validated_conn = fetch_query_params(conn)

      connect_info = %{
        peer_data: %{address: validated_conn.remote_ip, port: nil},
        x_headers: user_agent_headers(validated_conn),
        uri: URI.parse(request_url(validated_conn))
      }

      case SocketAuth.authenticate(validated_conn.query_params, connect_info) do
        {:ok, _claims} ->
          validated_conn

        {:error, reason} ->
          ip = format_ip(validated_conn.remote_ip) || "unknown"
          Logger.warning("ws_handshake_rejected ip=#{ip} reason=#{reason_to_string(reason)}")

          body =
            Jason.encode!(%{
              error: "unauthorized",
              reason: reason_to_string(reason)
            })

          validated_conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, body)
          |> halt()
      end
    else
      conn
    end
  end

  defp signaling_ws_request?(conn) do
    String.starts_with?(conn.request_path, @ws_path_prefix) and websocket_upgrade?(conn)
  end

  defp websocket_upgrade?(conn) do
    conn
    |> get_req_header("upgrade")
    |> Enum.any?(fn value -> String.downcase(value) == "websocket" end)
  end

  defp user_agent_headers(conn) do
    case get_req_header(conn, "user-agent") do
      [] -> []
      [ua | _] -> [{"user-agent", ua}]
    end
  end

  defp reason_to_string(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_to_string(reason), do: to_string(reason)

  defp format_ip(ip) when is_tuple(ip) do
    case :inet.ntoa(ip) do
      {:error, _} -> nil
      rendered -> to_string(rendered)
    end
  end

  defp format_ip(_), do: nil
end
