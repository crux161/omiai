defmodule OmiaiWeb.SignalingChannel do
  @moduledoc """
  WebRTC/QUIC signaling channel with multi-device support and Trickle ICE.

  Topic format: "user:{quicdial_id}" or "peer:{quicdial_id}"
  - All devices of a user join the same topic
  - Phoenix.Presence tracks active device_uuids
  - sdp_offer: broadcast to all devices (simultaneous ringing)
  - sdp_answer: broadcast call_resolved to callee topic, route answer to caller
  - ice_candidate: route to specific device_uuid for minimal latency
  - resolve_quicdial: look up a calling code in the QuicdialRegistry
  - register_startup: re-register the peer's IP on reconnect
  """

  use OmiaiWeb, :channel

  require Logger

  alias Omiai.Accounts
  alias OmiaiWeb.Presence
  alias OmiaiWeb.PairingTokenCache
  alias OmiaiWeb.QuicdialRegistry

  # ---------------------------------------------------------------------------
  # Join (accepts both user: and peer: prefixes)
  # ---------------------------------------------------------------------------

  @impl true
  def join("user:" <> requested_quicdial_id, _payload, socket) do
    do_join(requested_quicdial_id, socket)
  end

  @impl true
  def join("peer:" <> requested_quicdial_id, _payload, socket) do
    do_join(requested_quicdial_id, socket)
  end

  @impl true
  def join(_topic, _payload, _socket), do: {:error, %{reason: "invalid_topic"}}

  defp do_join(requested_quicdial_id, socket) do
    %{quicdial_id: authed_quicdial_id, device_uuid: device_uuid} = socket.assigns

    if requested_quicdial_id == authed_quicdial_id do
      {:ok, _meta} =
        Presence.track(socket, device_uuid, %{
          online_at: System.system_time(:second),
          node: Atom.to_string(node())
        })

      Logger.info(
        "device_joined quicdial_id=#{authed_quicdial_id} device_uuid=#{device_uuid} topic=#{socket.topic}"
      )

      {:ok, socket}
    else
      Logger.warning(
        "join_denied quicdial_id=#{authed_quicdial_id} requested=#{socket.topic} reason=unauthorized"
      )

      {:error, %{reason: "unauthorized_join"}}
    end
  end

  # ---------------------------------------------------------------------------
  # Pairing
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in("generate_pairing_token", _payload, socket) do
    %{quicdial_id: quicdial_id} = socket.assigns

    case PairingTokenCache.generate(quicdial_id) do
      {:ok, token} ->
        Logger.info("pairing_token_generated quicdial_id=#{quicdial_id}")

        {:reply, {:ok, %{"token" => token, "expires_in_seconds" => 300}}, socket}

      {:error, reason} ->
        Logger.warning("pairing_token_failed quicdial_id=#{quicdial_id} reason=#{inspect(reason)}")

        {:reply, {:error, %{"reason" => "token_generation_failed"}}, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Quicdial Resolution
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in("resolve_quicdial", %{"code" => code}, socket) when is_binary(code) do
    normalized = String.trim(code)

    case QuicdialRegistry.resolve(normalized) do
      {:ok, ip} ->
        Logger.info("resolve_quicdial code=#{normalized} ip=#{ip} by=#{socket.assigns.quicdial_id}")

        {:reply,
         {:ok,
          %{
            "ip" => ip,
            "ice_servers" => ice_servers()
          }}, socket}

      :error ->
        Logger.info("resolve_quicdial code=#{normalized} reason=offline by=#{socket.assigns.quicdial_id}")
        {:reply, {:error, %{"reason" => "offline"}}, socket}
    end
  end

  @impl true
  def handle_in("resolve_quicdial", _payload, socket) do
    {:reply, {:error, %{"reason" => "missing_code"}}, socket}
  end

  # ---------------------------------------------------------------------------
  # ICE Server Configuration
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in("get_ice_servers", _payload, socket) do
    {:reply, {:ok, %{"ice_servers" => ice_servers()}}, socket}
  end

  # ---------------------------------------------------------------------------
  # Server-Mediated Friend Requests
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in("friend_request", %{"to_quicdial_id" => to_quicdial_id}, socket) do
    user_id = socket.assigns[:user_id]

    if is_nil(user_id) do
      {:reply, {:error, %{"reason" => "auth_required"}}, socket}
    else
      case Accounts.send_friend_request(user_id, to_quicdial_id) do
        {:ok, friendship} ->
          user = Accounts.get_user!(user_id)

          broadcast_to_peer(to_quicdial_id, "friend_request_received", %{
            "friendship_id" => friendship.id,
            "from_quicdial_id" => user.quicdial_id,
            "from_display_name" => user.display_name,
            "from_avatar_id" => user.avatar_id
          })

          {:reply, {:ok, %{"friendship_id" => friendship.id}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{"reason" => to_string(reason)}}, socket}
      end
    end
  end

  @impl true
  def handle_in("friend_accept", %{"friendship_id" => friendship_id}, socket) do
    user_id = socket.assigns[:user_id]

    if is_nil(user_id) do
      {:reply, {:error, %{"reason" => "auth_required"}}, socket}
    else
      case Accounts.accept_friend_request(friendship_id, user_id) do
        {:ok, friendship} ->
          user = Accounts.get_user!(user_id)
          requester = Accounts.get_user!(friendship.requester_id)

          broadcast_to_peer(requester.quicdial_id, "friend_accepted", %{
            "friendship_id" => friendship.id,
            "by_quicdial_id" => user.quicdial_id,
            "by_display_name" => user.display_name,
            "by_avatar_id" => user.avatar_id
          })

          {:reply, {:ok, %{"status" => "accepted"}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{"reason" => to_string(reason)}}, socket}
      end
    end
  end

  @impl true
  def handle_in("friend_decline", %{"friendship_id" => friendship_id}, socket) do
    user_id = socket.assigns[:user_id]

    if is_nil(user_id) do
      {:reply, {:error, %{"reason" => "auth_required"}}, socket}
    else
      case Accounts.decline_friend_request(friendship_id, user_id) do
        {:ok, friendship} ->
          requester = Accounts.get_user!(friendship.requester_id)

          broadcast_to_peer(requester.quicdial_id, "friend_declined", %{
            "friendship_id" => friendship.id,
            "by_quicdial_id" => socket.assigns.quicdial_id
          })

          {:reply, {:ok, %{"status" => "declined"}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{"reason" => to_string(reason)}}, socket}
      end
    end
  end

  @impl true
  def handle_in("friend_remove", %{"quicdial_id" => target_quicdial_id}, socket) do
    user_id = socket.assigns[:user_id]

    if is_nil(user_id) do
      {:reply, {:error, %{"reason" => "auth_required"}}, socket}
    else
      case Accounts.remove_friendship(user_id, target_quicdial_id) do
        :ok ->
          broadcast_to_peer(target_quicdial_id, "friend_removed", %{
            "by_quicdial_id" => socket.assigns.quicdial_id
          })

          {:reply, {:ok, %{"status" => "removed"}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{"reason" => to_string(reason)}}, socket}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Startup Registration
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in("register_startup", _payload, socket) do
    %{quicdial_id: quicdial_id, peer_ip: peer_ip} = socket.assigns

    if peer_ip && peer_ip != "unknown" do
      QuicdialRegistry.register(quicdial_id, peer_ip, self())
      Logger.info("register_startup quicdial_id=#{quicdial_id} ip=#{peer_ip}")
    end

    {:reply, {:ok, %{"registered" => true}}, socket}
  end

  # ---------------------------------------------------------------------------
  # WebRTC Signaling: SDP Offer (Simultaneous Ringing)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in("sdp_offer", payload, socket) when is_map(payload) do
    %{quicdial_id: from_quicdial_id, device_uuid: from_device_uuid} = socket.assigns

    case fetch_target_quicdial_id(payload) do
      {:ok, to_quicdial_id} ->
        # Check presence on both user: and peer: topics
        user_presence = Presence.list("user:" <> to_quicdial_id)
        peer_presence = Presence.list("peer:" <> to_quicdial_id)

        if map_size(user_presence) == 0 and map_size(peer_presence) == 0 do
          Logger.info(
            "sdp_offer_fast_fail from=#{from_quicdial_id} to=#{to_quicdial_id} reason=offline"
          )

          push(socket, "peer_offline", %{
            "to" => to_quicdial_id,
            "reason" => "offline",
            "sent_at" => System.system_time(:millisecond)
          })

          {:reply, {:error, %{"reason" => "offline"}}, socket}
        else
          outbound =
            payload
            |> Map.put("from_quicdial_id", from_quicdial_id)
            |> Map.put("from_device_uuid", from_device_uuid)
            |> Map.put("to_quicdial_id", to_quicdial_id)
            |> Map.put("sent_at", System.system_time(:millisecond))

          # Broadcast to both topic prefixes so the callee receives regardless of which they joined
          broadcast_to_peer(to_quicdial_id, "sdp_offer", outbound)

          Logger.info(
            "sdp_offer_broadcast from=#{from_quicdial_id} to=#{to_quicdial_id} all_devices_ring"
          )

          {:reply, {:ok, %{"delivered" => true}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{"reason" => reason}}, socket}
    end
  end

  @impl true
  def handle_in("sdp_offer", _payload, socket) do
    {:reply, {:error, %{"reason" => "invalid_payload"}}, socket}
  end

  # ---------------------------------------------------------------------------
  # WebRTC Signaling: SDP Answer (Route to Caller, Stop Other Devices)
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in("sdp_answer", payload, socket) when is_map(payload) do
    %{quicdial_id: from_quicdial_id, device_uuid: from_device_uuid} = socket.assigns

    with {:ok, to_quicdial_id} <- fetch_string(payload, "to_quicdial_id"),
         {:ok, to_device_uuid} <- fetch_string(payload, "to_device_uuid") do
      # 1. Broadcast call_resolved to our topic so other devices stop ringing (exclude self)
      call_resolved_payload = %{
        "answered_by_device_uuid" => from_device_uuid,
        "to_quicdial_id" => to_quicdial_id,
        "sent_at" => System.system_time(:millisecond)
      }

      broadcast_from!(socket, "call_resolved", call_resolved_payload)

      # 2. Route answer to the caller's topics; caller filters by target_device_uuid
      answer_payload =
        payload
        |> Map.put("from_quicdial_id", from_quicdial_id)
        |> Map.put("from_device_uuid", from_device_uuid)
        |> Map.put("to_quicdial_id", to_quicdial_id)
        |> Map.put("target_device_uuid", to_device_uuid)
        |> Map.put("sent_at", System.system_time(:millisecond))

      broadcast_to_peer(to_quicdial_id, "sdp_answer", answer_payload)

      Logger.info(
        "sdp_answer_routed from=#{from_quicdial_id} to=#{to_quicdial_id}:#{to_device_uuid} call_resolved_broadcast"
      )

      {:reply, {:ok, %{"delivered" => true}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{"reason" => reason}}, socket}
    end
  end

  @impl true
  def handle_in("sdp_answer", _payload, socket) do
    {:reply, {:error, %{"reason" => "invalid_payload"}}, socket}
  end

  # ---------------------------------------------------------------------------
  # Trickle ICE: Route to Specific Device
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in("ice_candidate", payload, socket) when is_map(payload) do
    %{quicdial_id: from_quicdial_id, device_uuid: from_device_uuid} = socket.assigns

    with {:ok, to_quicdial_id} <- fetch_string(payload, "to_quicdial_id"),
         {:ok, to_device_uuid} <- fetch_string(payload, "to_device_uuid") do
      # Route only to the target device; payload includes target_device_uuid for client filtering
      outbound =
        payload
        |> Map.put("from_quicdial_id", from_quicdial_id)
        |> Map.put("from_device_uuid", from_device_uuid)
        |> Map.put("to_quicdial_id", to_quicdial_id)
        |> Map.put("target_device_uuid", to_device_uuid)
        |> Map.put("sent_at", System.system_time(:millisecond))

      broadcast_to_peer(to_quicdial_id, "ice_candidate", outbound)

      Logger.debug(
        "ice_candidate_routed from=#{from_quicdial_id} to=#{to_quicdial_id}:#{to_device_uuid}"
      )

      {:reply, {:ok, %{"delivered" => true}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{"reason" => reason}}, socket}
    end
  end

  @impl true
  def handle_in("ice_candidate", _payload, socket) do
    {:reply, {:error, %{"reason" => "invalid_payload"}}, socket}
  end

  # ---------------------------------------------------------------------------
  # Voicemail Dropbox
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in("voicemail_deposit", payload, socket) when is_map(payload) do
    %{quicdial_id: from_quicdial_id} = socket.assigns

    with {:ok, to_quicdial_id} <- fetch_string(payload, "to_quicdial_id"),
         {:ok, data_b64} <- fetch_string(payload, "data_b64") do
      metadata = payload["metadata"] || %{}

      case OmiaiWeb.VoicemailStore.deposit(to_quicdial_id, from_quicdial_id, data_b64, metadata) do
        {:ok, id} ->
          # Notify recipient if they're online
          broadcast_to_peer(to_quicdial_id, "voicemail_available", %{
            "id" => id,
            "from_quicdial_id" => from_quicdial_id,
            "metadata" => metadata,
            "sent_at" => System.system_time(:millisecond)
          })

          {:reply, {:ok, %{"id" => id}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{"reason" => reason}}, socket}
      end
    else
      {:error, reason} ->
        {:reply, {:error, %{"reason" => reason}}, socket}
    end
  end

  @impl true
  def handle_in("voicemail_deposit", _payload, socket) do
    {:reply, {:error, %{"reason" => "invalid_payload"}}, socket}
  end

  @impl true
  def handle_in("voicemail_check", _payload, socket) do
    %{quicdial_id: quicdial_id} = socket.assigns
    entries = OmiaiWeb.VoicemailStore.check(quicdial_id)
    {:reply, {:ok, %{"voicemails" => entries}}, socket}
  end

  @impl true
  def handle_in("voicemail_fetch", %{"id" => voicemail_id}, socket) when is_binary(voicemail_id) do
    %{quicdial_id: quicdial_id} = socket.assigns

    case OmiaiWeb.VoicemailStore.fetch(voicemail_id, quicdial_id) do
      {:ok, entry} ->
        {:reply, {:ok, %{
          "id" => entry.id,
          "from_quicdial_id" => entry.from_quicdial_id,
          "data_b64" => entry.data_b64,
          "metadata" => entry.metadata,
          "inserted_at" => entry.inserted_at
        }}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => reason}}, socket}
    end
  end

  @impl true
  def handle_in("voicemail_fetch", _payload, socket) do
    {:reply, {:error, %{"reason" => "missing_id"}}, socket}
  end

  # ---------------------------------------------------------------------------
  # Chat / Typing / File-Offer Relay
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in("relay_message", payload, socket) when is_map(payload) do
    %{quicdial_id: from_quicdial_id, device_uuid: from_device_uuid} = socket.assigns

    with {:ok, to_quicdial_id} <- fetch_string(payload, "to_quicdial_id") do
      outbound =
        payload
        |> Map.put("from_quicdial_id", from_quicdial_id)
        |> Map.put("from_device_uuid", from_device_uuid)
        |> Map.put("sent_at", System.system_time(:millisecond))

      broadcast_to_peer(to_quicdial_id, "relay_message", outbound)

      {:reply, {:ok, %{"delivered" => true}}, socket}
    else
      {:error, reason} ->
        {:reply, {:error, %{"reason" => reason}}, socket}
    end
  end

  @impl true
  def handle_in("relay_message", _payload, socket) do
    {:reply, {:error, %{"reason" => "invalid_payload"}}, socket}
  end

  # ---------------------------------------------------------------------------
  # Fallback
  # ---------------------------------------------------------------------------

  @impl true
  def handle_in(event, _payload, socket) do
    Logger.warning(
      "event_rejected quicdial_id=#{socket.assigns.quicdial_id} event=#{event} reason=invalid_event"
    )

    {:reply, {:error, %{"reason" => "invalid_event"}}, socket}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Broadcast to both user: and peer: topics so peers on either prefix receive the event
  defp broadcast_to_peer(quicdial_id, event, payload) do
    OmiaiWeb.Endpoint.broadcast("user:" <> quicdial_id, event, payload)
    OmiaiWeb.Endpoint.broadcast("peer:" <> quicdial_id, event, payload)
  end

  defp fetch_target_quicdial_id(payload) do
    case fetch_string(payload, "to_quicdial_id") do
      {:ok, id} -> {:ok, id}
      {:error, _} -> fetch_string(payload, "to")
    end
  end

  defp fetch_string(payload, key) when is_map(payload) do
    value = payload[key] || payload[to_string(key)]
    normalized = value |> to_string() |> String.trim()
    if normalized == "", do: {:error, "missing_#{key}"}, else: {:ok, normalized}
  end

  defp fetch_string(_payload, key), do: {:error, "missing_#{key}"}

  defp ice_servers do
    Application.get_env(:omiai, :ice_servers, [])
  end
end
