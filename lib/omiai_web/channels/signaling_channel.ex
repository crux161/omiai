defmodule OmiaiWeb.SignalingChannel do
  use OmiaiWeb, :channel

  require Logger

  alias OmiaiWeb.Presence

  @canonical_events ~w(sdp_offer sdp_answer ice_candidate)
  @legacy_to_canonical %{
    "offer" => "sdp_offer",
    "answer" => "sdp_answer",
    "ice" => "ice_candidate"
  }
  @canonical_to_legacy %{
    "sdp_offer" => "offer",
    "sdp_answer" => "answer",
    "ice_candidate" => "ice"
  }
  @routing_events @canonical_events ++ Map.keys(@legacy_to_canonical)
  @call_events ["friend?call", "friend_call"]

  @impl true
  def join(
        "peer:" <> requested_public_key,
        _payload,
        %Phoenix.Socket{assigns: %{public_key: authed_public_key, event_contract: event_contract}} =
          socket
      ) do
    if requested_public_key == authed_public_key do
      {:ok, _meta} =
        Presence.track(socket, authed_public_key, %{
          online_at: System.system_time(:second),
          event_contract: event_contract,
          node: Atom.to_string(node())
        })

      Logger.info(
        "peer_joined public_key=#{authed_public_key} topic=peer:#{requested_public_key} contract=#{event_contract}"
      )

      {:ok, socket}
    else
      Logger.warning(
        "peer_join_denied claimed=#{authed_public_key} requested_topic=peer:#{requested_public_key} reason=unauthorized_join"
      )

      {:error, %{reason: "unauthorized_join"}}
    end
  end

  @impl true
  def join(_topic, _payload, _socket), do: {:error, %{reason: "invalid_topic"}}

  @impl true
  def handle_in(event, payload, socket) when event in @routing_events do
    case route_webrtc_event(event, payload, socket) do
      {:ok, metadata} ->
        {:reply, {:ok, metadata}, socket}

      {:error, reason} ->
        {:reply, {:error, %{"reason" => reason}}, socket}
    end
  end

  @impl true
  def handle_in(event, payload, socket) when event in @call_events do
    case fetch_to_public_key(payload) do
      {:ok, to_public_key} ->
        case Presence.list(topic_for(to_public_key)) do
          presence when map_size(presence) == 0 ->
            payload = offline_payload(to_public_key)

            Logger.info(
              "call_fast_fail from=#{socket.assigns.public_key} to=#{to_public_key} event=#{event} reason=offline"
            )

            push(socket, "peer_offline", payload)
            {:reply, {:error, %{"reason" => "offline"}}, socket}

          _presence ->
            outbound_payload =
              with_common_fields(payload, socket.assigns.public_key, to_public_key)

            OmiaiWeb.Endpoint.broadcast(topic_for(to_public_key), event, outbound_payload)

            Logger.info(
              "call_forwarded from=#{socket.assigns.public_key} to=#{to_public_key} event=#{event}"
            )

            {:reply, {:ok, %{"delivered" => true}}, socket}
        end

      {:error, reason} ->
        Logger.warning(
          "call_rejected from=#{socket.assigns.public_key} event=#{event} reason=#{reason}"
        )

        {:reply, {:error, %{"reason" => reason}}, socket}
    end
  end

  @impl true
  def handle_in(event, _payload, socket) do
    Logger.warning(
      "event_rejected from=#{socket.assigns.public_key} event=#{event} reason=invalid_event"
    )

    {:reply, {:error, %{"reason" => "invalid_event"}}, socket}
  end

  defp route_webrtc_event(event, payload, socket) do
    with {:ok, to_public_key} <- fetch_to_public_key(payload),
         recipient_presence when map_size(recipient_presence) > 0 <-
           Presence.list(topic_for(to_public_key)) do
      canonical_event = to_canonical_event(event)
      outbound_event = outbound_event_for_recipient(canonical_event, recipient_presence)

      outbound_payload = with_common_fields(payload, socket.assigns.public_key, to_public_key)

      OmiaiWeb.Endpoint.broadcast(topic_for(to_public_key), outbound_event, outbound_payload)

      Logger.info(
        "signal_routed from=#{socket.assigns.public_key} to=#{to_public_key} event=#{outbound_event}"
      )

      {:ok,
       %{
         "delivered" => true,
         "event" => outbound_event,
         "to" => to_public_key
       }}
    else
      {:error, reason} ->
        Logger.warning(
          "signal_rejected from=#{socket.assigns.public_key} event=#{event} reason=#{reason}"
        )

        {:error, reason}

      _offline_presence ->
        Logger.info(
          "signal_fast_fail from=#{socket.assigns.public_key} event=#{event} reason=offline"
        )

        {:error, "offline"}
    end
  end

  defp fetch_to_public_key(payload) when is_map(payload) do
    case payload |> Map.get("to") |> normalize_public_key() do
      nil -> {:error, "missing_to"}
      to_public_key -> {:ok, to_public_key}
    end
  end

  defp fetch_to_public_key(_payload), do: {:error, "invalid_payload"}

  defp normalize_public_key(nil), do: nil

  defp normalize_public_key(value) do
    normalized = value |> to_string() |> String.trim()
    if normalized == "", do: nil, else: normalized
  end

  defp to_canonical_event(event), do: Map.get(@legacy_to_canonical, event, event)

  defp outbound_event_for_recipient(canonical_event, presence_entries) do
    case recipient_contract(presence_entries) do
      "legacy" -> Map.get(@canonical_to_legacy, canonical_event, canonical_event)
      _ -> canonical_event
    end
  end

  defp recipient_contract(presence_entries) do
    contracts =
      presence_entries
      |> Map.values()
      |> Enum.flat_map(&Map.get(&1, :metas, []))
      |> Enum.map(&Map.get(&1, :event_contract, "dual"))

    cond do
      Enum.any?(contracts, &(&1 in ["sdp", "dual"])) -> "sdp"
      Enum.any?(contracts, &(&1 == "legacy")) -> "legacy"
      true -> "dual"
    end
  end

  defp with_common_fields(payload, from_public_key, to_public_key) do
    payload
    |> Map.put("from", from_public_key)
    |> Map.put("to", to_public_key)
    |> Map.put("sent_at", System.system_time(:millisecond))
  end

  defp offline_payload(to_public_key) do
    %{
      "to" => to_public_key,
      "reason" => "offline",
      "trigger" => "friend_call",
      "sent_at" => System.system_time(:millisecond)
    }
  end

  defp topic_for(public_key), do: "peer:" <> public_key
end
