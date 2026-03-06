defmodule OmiaiWeb.SankakuSocket do
  @moduledoc """
  Multi-device WebRTC/QUIC signaling socket.

  Accepts connections with:
  - auth_token + device_uuid (logged-in Omiai user)
  - pairing_token + device_uuid (QR code pairing)
  - quicdial_id/public_key + device_uuid (LAN fallback)
  """

  use Phoenix.Socket

  require Logger

  alias OmiaiWeb.Auth.SocketAuth
  alias OmiaiWeb.QuicdialRegistry

  channel "user:*", OmiaiWeb.SignalingChannel
  channel "peer:*", OmiaiWeb.SignalingChannel
  channel "lobby:*", OmiaiWeb.LobbyChannel

  @impl true
  def connect(params, socket, connect_info) do
    case SocketAuth.authenticate(params, connect_info) do
      {:ok, claims} ->
        ip = extract_peer_ip(connect_info) || claims.client_meta[:ip] || "unknown"
        client_meta = Map.put(claims.client_meta, :ip, ip)

        maybe_register_quicdial(claims.quicdial_id, ip)

        Logger.info(
          "socket_connected quicdial_id=#{claims.quicdial_id} device_uuid=#{claims.device_uuid} ip=#{ip}"
        )

        authed_socket =
          socket
          |> assign(:quicdial_id, claims.quicdial_id)
          |> assign(:device_uuid, claims.device_uuid)
          |> assign(:peer_ip, ip)
          |> assign(:client_meta, client_meta)
          |> assign(:user_id, Map.get(claims, :user_id))

        {:ok, authed_socket}

      {:error, reason} ->
        Logger.warning("socket_rejected reason=#{inspect(reason)}")
        :error
    end
  end

  @impl true
  def id(%Phoenix.Socket{assigns: %{quicdial_id: quicdial_id, device_uuid: device_uuid}}) do
    "user:#{quicdial_id}:#{device_uuid}"
  end

  defp maybe_register_quicdial(_quicdial_id, "unknown"), do: :ok

  defp maybe_register_quicdial(quicdial_id, ip),
    do: QuicdialRegistry.register(quicdial_id, ip, self())

  defp extract_peer_ip(connect_info) when is_map(connect_info) do
    peer_data = Map.get(connect_info, :peer_data) || Map.get(connect_info, "peer_data") || %{}

    case peer_data do
      %{address: address} -> normalize_ip(address)
      %{"address" => address} -> normalize_ip(address)
      _ -> nil
    end
  end

  defp extract_peer_ip(_), do: nil

  defp normalize_ip({_, _, _, _} = address_tuple), do: tuple_to_ip(address_tuple)
  defp normalize_ip({_, _, _, _, _, _, _, _} = address_tuple), do: tuple_to_ip(address_tuple)

  defp normalize_ip(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      ip -> ip
    end
  end

  defp normalize_ip(value) when is_list(value) do
    value |> to_string() |> normalize_ip()
  end

  defp normalize_ip(_), do: nil

  defp tuple_to_ip(address_tuple) do
    case :inet.ntoa(address_tuple) do
      {:error, _} -> nil
      ip -> to_string(ip)
    end
  end
end
