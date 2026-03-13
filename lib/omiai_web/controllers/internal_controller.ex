defmodule OmiaiWeb.InternalController do
  @moduledoc """
  Webhook receiver for the external Python backend.

  The Python service calls these endpoints when it has made a matchmaking
  decision or needs to push a real-time event to connected user sockets.
  All routes are protected by a shared API key via InternalAuth plug.
  """

  use OmiaiWeb, :controller

  require Logger

  @doc """
  POST /internal/match_found

  Receives a payload specifying two matched peers and a session_id.
  Broadcasts a "match_found" event to both peers via PubSub.

  Expected body:
    {
      "peer_a": "<quicdial_id>",
      "peer_b": "<quicdial_id>",
      "session_id": "<unique session identifier>",
      "metadata": { ... }            // optional
    }
  """
  def match_found(conn, %{"peer_a" => peer_a, "peer_b" => peer_b, "session_id" => session_id} = params) do
    metadata = params["metadata"] || %{}

    payload = %{
      "session_id" => session_id,
      "peer_a" => peer_a,
      "peer_b" => peer_b,
      "metadata" => metadata,
      "sent_at" => System.system_time(:millisecond)
    }

    broadcast_to_peer(peer_a, "match_found", Map.put(payload, "matched_with", peer_b))
    broadcast_to_peer(peer_b, "match_found", Map.put(payload, "matched_with", peer_a))

    Logger.info("match_found session_id=#{session_id} peer_a=#{peer_a} peer_b=#{peer_b}")

    json(conn, %{status: "broadcast_sent", session_id: session_id})
  end

  def match_found(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_fields", details: "peer_a, peer_b, and session_id required"})
  end

  @doc """
  POST /internal/push_event

  Generic event push endpoint. The Python backend can push any event
  to a specific user's connected sockets.

  Expected body:
    {
      "to_quicdial_id": "<quicdial_id>",
      "event": "<event_name>",
      "payload": { ... }
    }
  """
  def push_event(conn, %{"to_quicdial_id" => to, "event" => event, "payload" => payload}) do
    broadcast_to_peer(to, event, Map.put(payload, "sent_at", System.system_time(:millisecond)))

    Logger.info("push_event to=#{to} event=#{event}")

    json(conn, %{status: "broadcast_sent"})
  end

  def push_event(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_fields", details: "to_quicdial_id, event, and payload required"})
  end

  defp broadcast_to_peer(quicdial_id, event, payload) do
    OmiaiWeb.Endpoint.broadcast("user:" <> quicdial_id, event, payload)
    OmiaiWeb.Endpoint.broadcast("peer:" <> quicdial_id, event, payload)
  end
end
