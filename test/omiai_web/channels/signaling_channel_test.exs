defmodule OmiaiWeb.SignalingChannelTest do
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest

  alias OmiaiWeb.{Presence, SankakuSocket, SignalingChannel}

  @endpoint OmiaiWeb.Endpoint

  test "sdp_offer routes canonical event for dual recipient" do
    {:ok, _bob} = connect_and_join("bob_key", "dual")
    {:ok, alice} = connect_and_join("alice_key", "dual")

    ref =
      push(alice, "sdp_offer", %{"to" => "bob_key", "call_id" => "call_1", "sdp" => "REDACTED"})

    assert_reply ref, :ok, %{"delivered" => true, "event" => "sdp_offer", "to" => "bob_key"}

    assert_broadcast "sdp_offer", %{
      "to" => "bob_key",
      "from" => "alice_key",
      "call_id" => "call_1",
      "sent_at" => sent_at
    }

    assert is_integer(sent_at)
  end

  test "sdp_offer routes legacy event for legacy recipient" do
    {:ok, _bob} = connect_and_join("bob_legacy", "legacy")
    {:ok, alice} = connect_and_join("alice_dual", "dual")

    ref = push(alice, "sdp_offer", %{"to" => "bob_legacy", "sdp" => "REDACTED"})

    assert_reply ref, :ok, %{"delivered" => true, "event" => "offer", "to" => "bob_legacy"}

    assert_broadcast "offer", %{
      "to" => "bob_legacy",
      "from" => "alice_dual",
      "sent_at" => sent_at
    }

    assert is_integer(sent_at)
  end

  test "legacy offer input normalizes to canonical recipient event" do
    {:ok, _bob} = connect_and_join("bob_sdp", "sdp")
    {:ok, alice} = connect_and_join("alice_legacy_sender", "dual")

    ref = push(alice, "offer", %{"to" => "bob_sdp", "sdp" => "REDACTED"})

    assert_reply ref, :ok, %{"delivered" => true, "event" => "sdp_offer", "to" => "bob_sdp"}

    assert_broadcast "sdp_offer", %{
      "to" => "bob_sdp",
      "from" => "alice_legacy_sender",
      "sent_at" => sent_at
    }

    assert is_integer(sent_at)
  end

  test "ice routing supports legacy and canonical names" do
    {:ok, _bob_legacy} = connect_and_join("bob_legacy_ice", "legacy")
    {:ok, alice} = connect_and_join("alice_ice", "dual")

    ref = push(alice, "ice_candidate", %{"to" => "bob_legacy_ice", "candidate" => "candidate:1"})

    assert_reply ref, :ok, %{"delivered" => true, "event" => "ice", "to" => "bob_legacy_ice"}

    assert_broadcast "ice", %{
      "to" => "bob_legacy_ice",
      "from" => "alice_ice",
      "sent_at" => sent_at
    }

    assert is_integer(sent_at)

    {:ok, _bob_dual} = connect_and_join("bob_dual_ice", "dual")

    ref2 = push(alice, "ice", %{"to" => "bob_dual_ice", "candidate" => "candidate:2"})

    assert_reply ref2, :ok, %{
      "delivered" => true,
      "event" => "ice_candidate",
      "to" => "bob_dual_ice"
    }

    assert_broadcast "ice_candidate", %{
      "to" => "bob_dual_ice",
      "from" => "alice_ice",
      "sent_at" => sent_at_2
    }

    assert is_integer(sent_at_2)
  end

  test "friend?call fast-fails when peer is offline" do
    {:ok, alice} = connect_and_join("alice_call", "dual")

    ref = push(alice, "friend?call", %{"to" => "offline_bob", "call_id" => "call_2"})

    assert_reply ref, :error, %{"reason" => "offline"}

    assert_push "peer_offline", %{
      "to" => "offline_bob",
      "reason" => "offline",
      "trigger" => "friend_call",
      "sent_at" => sent_at
    }

    assert is_integer(sent_at)
  end

  test "friend?call forwards when peer is online" do
    {:ok, _bob} = connect_and_join("online_bob", "dual")
    {:ok, alice} = connect_and_join("alice_online_call", "dual")

    ref = push(alice, "friend?call", %{"to" => "online_bob", "call_id" => "call_3"})

    assert_reply ref, :ok, %{"delivered" => true}

    assert_broadcast "friend?call", %{
      "to" => "online_bob",
      "from" => "alice_online_call",
      "call_id" => "call_3",
      "sent_at" => sent_at
    }

    assert is_integer(sent_at)
  end

  test "malformed payload missing to returns missing_to" do
    {:ok, alice} = connect_and_join("alice_bad_payload", "dual")

    ref = push(alice, "sdp_offer", %{"sdp" => "REDACTED"})

    assert_reply ref, :error, %{"reason" => "missing_to"}
  end

  test "presence metadata is tracked on join and removed on disconnect" do
    Process.flag(:trap_exit, true)

    {:ok, channel_socket} = connect_and_join("presence_peer", "legacy")

    presence = Presence.list("peer:presence_peer")
    assert map_size(presence) > 0

    metas =
      presence
      |> Map.values()
      |> Enum.flat_map(&Map.get(&1, :metas, []))

    assert Enum.any?(metas, fn meta ->
             Map.get(meta, :event_contract) == "legacy" and is_integer(Map.get(meta, :online_at)) and
               is_binary(Map.get(meta, :node))
           end)

    leave_ref = leave(channel_socket)
    assert_reply leave_ref, :ok

    assert_presence_cleared("peer:presence_peer")
  end

  defp connect_and_join(public_key, contract) do
    assert {:ok, socket} =
             connect(SankakuSocket, %{"public_key" => public_key, "event_contract" => contract})

    assert {:ok, _reply, channel_socket} =
             subscribe_and_join(socket, SignalingChannel, "peer:" <> public_key)

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
