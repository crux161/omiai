defmodule OmiaiWeb.LobbyChannel do
  @moduledoc """
  Global peer discovery channel.

  All connected peers join "lobby:sankaku" and are tracked via Presence.
  When a peer joins, all other peers receive a presence_diff showing the new
  peer's quicdial_id, display_name, avatar_id, and IP — enabling automatic
  peer list population dictated by the Omiai server.
  """

  use OmiaiWeb, :channel

  require Logger

  alias Omiai.Accounts
  alias OmiaiWeb.Presence
  alias OmiaiWeb.QuicdialRegistry

  @lobby_topic "lobby:sankaku"

  @impl true
  def join(@lobby_topic, _payload, socket) do
    send(self(), :after_join)
    {:ok, socket}
  end

  @impl true
  def join(_topic, _payload, _socket), do: {:error, %{reason: "invalid_lobby_topic"}}

  @impl true
  def handle_info(:after_join, socket) do
    %{quicdial_id: quicdial_id, device_uuid: device_uuid, peer_ip: peer_ip} = socket.assigns

    # Look up user from DB to get display_name and avatar_id
    user_meta =
      case Accounts.get_user_by_quicdial_id(quicdial_id) do
        nil -> %{display_name: quicdial_id, avatar_id: "default"}
        user -> %{display_name: user.display_name, avatar_id: user.avatar_id}
      end

    # Track this peer in lobby presence so all other peers see them
    {:ok, _} =
      Presence.track(socket, quicdial_id, %{
        device_uuid: device_uuid,
        ip: peer_ip,
        display_name: user_meta.display_name,
        avatar_id: user_meta.avatar_id,
        online_at: System.system_time(:second),
        node: Atom.to_string(node())
      })

    # Push the full current peer list to the joining peer
    push(socket, "presence_state", Presence.list(socket))

    Logger.info(
      "lobby_joined quicdial_id=#{quicdial_id} device_uuid=#{device_uuid} ip=#{peer_ip} display_name=#{user_meta.display_name}"
    )

    {:noreply, socket}
  end

  @impl true
  def handle_in("list_peers", _payload, socket) do
    peers =
      Presence.list(socket)
      |> Enum.map(fn {quicdial_id, %{metas: metas}} ->
        latest = List.last(metas)

        %{
          "quicdial_id" => quicdial_id,
          "display_name" => latest[:display_name] || quicdial_id,
          "avatar_id" => latest[:avatar_id] || "default",
          "ip" => latest[:ip] || resolve_ip(quicdial_id),
          "device_uuid" => latest[:device_uuid],
          "online_at" => latest[:online_at]
        }
      end)

    {:reply, {:ok, %{"peers" => peers}}, socket}
  end

  @impl true
  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{"reason" => "invalid_event"}}, socket}
  end

  defp resolve_ip(quicdial_id) do
    case QuicdialRegistry.resolve(quicdial_id) do
      {:ok, ip} -> ip
      :error -> nil
    end
  end
end
