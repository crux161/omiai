defmodule OmiaiWeb.LobbyChannel do
  @moduledoc """
  Global peer discovery and matchmaking proxy channel.

  All connected peers join "lobby:sankaku" and are tracked via Presence.
  User metadata (display_name, avatar_id) is sourced from JWT claims
  carried in socket assigns — no database lookup required.

  Matchmaking requests are proxied asynchronously to the external Python
  backend via Req. The backend calls back via the internal webhook when
  a match decision is made.
  """

  use OmiaiWeb, :channel

  require Logger

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

    # User metadata comes from JWT claims in socket assigns — no DB lookup
    display_name = socket.assigns[:display_name] || quicdial_id
    avatar_id = socket.assigns[:avatar_id] || "default"

    {:ok, _} =
      Presence.track(socket, quicdial_id, %{
        device_uuid: device_uuid,
        ip: peer_ip,
        display_name: display_name,
        avatar_id: avatar_id,
        online_at: System.system_time(:second),
        node: Atom.to_string(node())
      })

    push(socket, "presence_state", Presence.list(socket))

    Logger.info(
      "lobby_joined quicdial_id=#{quicdial_id} device_uuid=#{device_uuid} ip=#{peer_ip} display_name=#{display_name}"
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
  def handle_in("find_match", payload, socket) do
    %{quicdial_id: quicdial_id, user_id: user_id} = socket.assigns

    backend_url = Application.get_env(:omiai, :backend_url)

    if backend_url do
      # Fire-and-forget async POST to Python backend; reply immediately
      Task.start(fn ->
        Req.post("#{backend_url}/matchmaking/enqueue",
          json: %{
            user_id: user_id,
            quicdial_id: quicdial_id,
            payload: payload
          },
          receive_timeout: 10_000
        )
      end)

      {:reply, {:ok, %{"status" => "queued"}}, socket}
    else
      {:reply, {:error, %{"reason" => "backend_not_configured"}}, socket}
    end
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
