defmodule OmiaiWeb.SankakuSocket do
  use Phoenix.Socket

  require Logger

  alias OmiaiWeb.Auth.SocketAuth
  alias OmiaiWeb.QuicdialRegistry

  channel "peer:*", OmiaiWeb.SignalingChannel

  @impl true
  def connect(params, socket, connect_info) do
    case SocketAuth.authenticate(params, connect_info) do
      {:ok, claims} ->
        ip = extract_peer_ip(connect_info) || claims.client_meta[:ip] || "unknown"
        client_meta = Map.put(claims.client_meta, :ip, ip)

        maybe_register_quicdial(claims.public_key, ip)

        Logger.info(
          "socket_connected public_key=#{claims.public_key} contract=#{claims.event_contract} ip=#{ip}"
        )

        authed_socket =
          socket
          |> assign(:public_key, claims.public_key)
          |> assign(:event_contract, claims.event_contract)
          |> assign(:peer_ip, ip)
          |> assign(:client_meta, client_meta)

        {:ok, authed_socket}

      {:error, reason} ->
        Logger.warning("socket_rejected reason=#{inspect(reason)}")
        :error
    end
  end

  @impl true
  def id(%Phoenix.Socket{assigns: %{public_key: public_key}}), do: "peer:" <> public_key

  defp maybe_register_quicdial(_public_key, "unknown"), do: :ok

  defp maybe_register_quicdial(public_key, ip),
    do: QuicdialRegistry.register(public_key, ip, self())

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
