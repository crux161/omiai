defmodule OmiaiWeb.SankakuSocketTest do
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest

  alias OmiaiWeb.{QuicdialRegistry, SankakuSocket, SignalingChannel}

  @endpoint OmiaiWeb.Endpoint

  test "connect accepts quicdial_id and device_uuid" do
    quicdial_id = "alice_quicdial"
    device_uuid = "device-desktop-001"

    assert {:ok, socket} =
             connect(
               SankakuSocket,
               %{"quicdial_id" => quicdial_id, "device_uuid" => device_uuid},
               connect_info: %{peer_data: %{address: {127, 0, 0, 1}, port: 45_001}}
             )

    assert socket.assigns.quicdial_id == quicdial_id
    assert socket.assigns.device_uuid == device_uuid
    assert is_map(socket.assigns.client_meta)
    assert socket.assigns.peer_ip == "127.0.0.1"
    assert {:ok, "127.0.0.1"} = QuicdialRegistry.resolve(quicdial_id)
  end

  test "connect captures ipv6 peer addresses from peer_data" do
    quicdial_id = "alice_ipv6"
    device_uuid = "device-001"

    assert {:ok, socket} =
             connect(
               SankakuSocket,
               %{"quicdial_id" => quicdial_id, "device_uuid" => device_uuid},
               connect_info: %{peer_data: %{address: {0, 0, 0, 0, 0, 0, 0, 1}, port: 45_002}}
             )

    assert is_binary(socket.assigns.peer_ip)
    assert String.contains?(socket.assigns.peer_ip, ":")
    assert {:ok, resolved_ip} = QuicdialRegistry.resolve(quicdial_id)
    assert resolved_ip == socket.assigns.peer_ip
  end

  test "connect rejects missing quicdial_id" do
    assert :error = connect(SankakuSocket, %{"device_uuid" => "device-001"})
  end

  test "connect auto-generates device_uuid when missing" do
    assert {:ok, socket} = connect(SankakuSocket, %{"quicdial_id" => "alice"})
    assert socket.assigns.quicdial_id == "alice"
    assert is_binary(socket.assigns.device_uuid)
    assert String.length(socket.assigns.device_uuid) > 0
  end

  test "connect accepts public_key as alias for quicdial_id" do
    assert {:ok, socket} =
             connect(
               SankakuSocket,
               %{"public_key" => "056-569-337", "device_uuid" => "device-iphone-001"},
               connect_info: %{peer_data: %{address: {192, 168, 1, 50}, port: 45_010}}
             )

    assert socket.assigns.quicdial_id == "056-569-337"
    assert socket.assigns.device_uuid == "device-iphone-001"
    assert socket.assigns.peer_ip == "192.168.1.50"
    assert {:ok, "192.168.1.50"} = QuicdialRegistry.resolve("056-569-337")
  end

  test "connect accepts public_key without device_uuid (desktop peer)" do
    assert {:ok, socket} =
             connect(
               SankakuSocket,
               %{"public_key" => "902-582-325", "session_token" => "902-582-325.123.abc"},
               connect_info: %{peer_data: %{address: {192, 168, 1, 100}, port: 45_011}}
             )

    assert socket.assigns.quicdial_id == "902-582-325"
    assert is_binary(socket.assigns.device_uuid)
    assert socket.assigns.peer_ip == "192.168.1.100"
  end

  test "connect accepts pairing_token and device_uuid when token is valid" do
    quicdial_id = "bob_quicdial"
    device_uuid = "device-mobile-002"

    {:ok, token} = OmiaiWeb.PairingTokenCache.generate(quicdial_id)

    assert {:ok, socket} =
             connect(
               SankakuSocket,
               %{"pairing_token" => token, "device_uuid" => device_uuid},
               connect_info: %{peer_data: %{address: {127, 0, 0, 1}, port: 45_003}}
             )

    assert socket.assigns.quicdial_id == quicdial_id
    assert socket.assigns.device_uuid == device_uuid
  end

  test "connect rejects invalid pairing_token" do
    assert :error =
             connect(
               SankakuSocket,
               %{"pairing_token" => "000000", "device_uuid" => "device-001"},
               connect_info: %{peer_data: %{address: {127, 0, 0, 1}, port: 45_004}}
             )
  end

  test "join rejects mismatched user topic" do
    assert {:ok, socket} =
             connect(
               SankakuSocket,
               %{"quicdial_id" => "alice", "device_uuid" => "device-001"},
               connect_info: %{peer_data: %{address: {127, 0, 0, 1}, port: 45_005}}
             )

    assert {:error, %{reason: "unauthorized_join"}} =
             subscribe_and_join(socket, SignalingChannel, "user:bob")
  end
end
