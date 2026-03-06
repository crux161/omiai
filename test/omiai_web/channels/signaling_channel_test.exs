defmodule OmiaiWeb.SignalingChannelTest do
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest

  alias OmiaiWeb.{Presence, SankakuSocket, SignalingChannel}

  @endpoint OmiaiWeb.Endpoint

  test "sdp_offer broadcasts to all devices (simultaneous ringing)" do
    {:ok, _bob} = connect_and_join("bob_key", "bob-device-1")
    {:ok, alice} = connect_and_join("alice_key", "alice-device-1")

    ref =
      push(alice, "sdp_offer", %{
        "to_quicdial_id" => "bob_key",
        "call_id" => "call_1",
        "sdp" => "REDACTED"
      })

    assert_reply ref, :ok, %{"delivered" => true}

    assert_broadcast "sdp_offer", %{
      "to_quicdial_id" => "bob_key",
      "from_quicdial_id" => "alice_key",
      "from_device_uuid" => "alice-device-1",
      "call_id" => "call_1",
      "sent_at" => sent_at
    }

    assert is_integer(sent_at)
  end

  test "sdp_offer fast-fails when target is offline" do
    {:ok, alice} = connect_and_join("alice_offline", "alice-dev-1")

    ref =
      push(alice, "sdp_offer", %{
        "to_quicdial_id" => "offline_bob",
        "sdp" => "REDACTED"
      })

    assert_reply ref, :error, %{"reason" => "offline"}

    assert_push "peer_offline", %{
      "to" => "offline_bob",
      "reason" => "offline",
      "sent_at" => sent_at
    }

    assert is_integer(sent_at)
  end

  test "sdp_offer accepts to as alias for to_quicdial_id" do
    {:ok, _bob} = connect_and_join("bob_alias", "bob-dev-1")
    {:ok, alice} = connect_and_join("alice_alias", "alice-dev-1")

    ref = push(alice, "sdp_offer", %{"to" => "bob_alias", "sdp" => "REDACTED"})

    assert_reply ref, :ok, %{"delivered" => true}
    assert_broadcast "sdp_offer", %{"to_quicdial_id" => "bob_alias", "from_quicdial_id" => "alice_alias"}
  end

  test "sdp_answer routes to caller and broadcasts call_resolved" do
    {:ok, bob} = connect_and_join("bob_answer", "bob-dev-1")
    {:ok, alice} = connect_and_join("alice_answer", "alice-dev-1")

    # Alice offers to Bob
    push(alice, "sdp_offer", %{
      "to_quicdial_id" => "bob_answer",
      "sdp" => "OFFER_SDP"
    })

    assert_broadcast "sdp_offer", _payload

    # Bob answers
    ref =
      push(bob, "sdp_answer", %{
        "to_quicdial_id" => "alice_answer",
        "to_device_uuid" => "alice-dev-1",
        "sdp" => "ANSWER_SDP"
      })

    assert_reply ref, :ok, %{"delivered" => true}

    # Alice receives the answer
    assert_broadcast "sdp_answer", %{
      "from_quicdial_id" => "bob_answer",
      "target_device_uuid" => "alice-dev-1",
      "sdp" => "ANSWER_SDP"
    }

    # call_resolved is broadcast to Bob's topic (other devices)
    assert_broadcast "call_resolved", %{
      "answered_by_device_uuid" => "bob-dev-1",
      "to_quicdial_id" => "alice_answer"
    }
  end

  test "ice_candidate routes to target device" do
    {:ok, _bob} = connect_and_join("bob_ice", "bob-dev-1")
    {:ok, alice} = connect_and_join("alice_ice", "alice-dev-1")

    ref =
      push(alice, "ice_candidate", %{
        "to_quicdial_id" => "bob_ice",
        "to_device_uuid" => "bob-dev-1",
        "candidate" => "candidate:1"
      })

    assert_reply ref, :ok, %{"delivered" => true}

    assert_broadcast "ice_candidate", %{
      "to_quicdial_id" => "bob_ice",
      "target_device_uuid" => "bob-dev-1",
      "from_quicdial_id" => "alice_ice",
      "candidate" => "candidate:1",
      "sent_at" => sent_at
    }

    assert is_integer(sent_at)
  end

  test "ice_candidate rejects missing to_device_uuid" do
    {:ok, _bob} = connect_and_join("bob_ice_missing", "bob-dev-1")
    {:ok, alice} = connect_and_join("alice_ice_missing", "alice-dev-1")

    ref =
      push(alice, "ice_candidate", %{
        "to_quicdial_id" => "bob_ice_missing",
        "candidate" => "candidate:1"
      })

    assert_reply ref, :error, %{"reason" => "missing_to_device_uuid"}
  end

  test "generate_pairing_token returns 6-digit token" do
    {:ok, alice} = connect_and_join("alice_pair", "alice-dev-1")

    ref = push(alice, "generate_pairing_token", %{})

    assert_reply ref, :ok, %{"token" => token, "expires_in_seconds" => 300}
    assert is_binary(token)
    assert String.length(token) == 6
    assert String.match?(token, ~r/^\d{6}$/)
  end

  test "malformed sdp_offer missing to returns error" do
    {:ok, alice} = connect_and_join("alice_bad", "alice-dev-1")

    ref = push(alice, "sdp_offer", %{"sdp" => "REDACTED"})

    assert_reply ref, :error, payload
    assert payload["reason"] in ["missing_to", "missing_to_quicdial_id"]
  end

  test "presence tracks device_uuid on join and clears on disconnect" do
    Process.flag(:trap_exit, true)

    {:ok, channel_socket} = connect_and_join("presence_peer", "presence-device-1")

    presence = Presence.list("user:presence_peer")
    assert map_size(presence) > 0
    assert Map.has_key?(presence, "presence-device-1")

    metas =
      presence
      |> Map.values()
      |> Enum.flat_map(&Map.get(&1, :metas, []))

    assert Enum.any?(metas, fn meta ->
             is_integer(Map.get(meta, :online_at)) and is_binary(Map.get(meta, :node))
           end)

    leave_ref = leave(channel_socket)
    assert_reply leave_ref, :ok

    assert_presence_cleared("user:presence_peer")
  end

  test "invalid_event returns error" do
    {:ok, alice} = connect_and_join("alice_invalid", "alice-dev-1")

    ref = push(alice, "unknown_event", %{})

    assert_reply ref, :error, %{"reason" => "invalid_event"}
  end

  defp connect_and_join(quicdial_id, device_uuid, opts \\ []) do
    peer_ip = Keyword.get(opts, :peer_ip, {127, 0, 0, 1})
    peer_port = Keyword.get(opts, :peer_port, 40_000)
    connect_info = %{peer_data: %{address: peer_ip, port: peer_port}}

    assert {:ok, socket} =
             connect(
               SankakuSocket,
               %{"quicdial_id" => quicdial_id, "device_uuid" => device_uuid},
               connect_info: connect_info
             )

    assert {:ok, _reply, channel_socket} =
             subscribe_and_join(socket, SignalingChannel, "user:" <> quicdial_id)

    {:ok, channel_socket}
  end

  defp assert_presence_cleared(topic, retries \\ 20)

  defp assert_presence_cleared(topic, 0) do
    assert Presence.list(topic) == %{}
  end

  defp assert_presence_cleared(topic, retries) do
    if Presence.list(topic) == %{} do
      assert true
    else
      Process.sleep(10)
      assert_presence_cleared(topic, retries - 1)
    end
  end
end
