defmodule OmiaiWeb.SankakuSocketTest do
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest

  alias OmiaiWeb.{QuicdialRegistry, SankakuSocket, SignalingChannel}

  @endpoint OmiaiWeb.Endpoint

  test "connect accepts public_key and applies default contract" do
    public_key = "alice_pub_key_connect"

    assert {:ok, socket} =
             connect(
               SankakuSocket,
               %{"public_key" => public_key},
               connect_info: %{peer_data: %{address: {127, 0, 0, 1}, port: 45_001}}
             )

    assert socket.assigns.public_key == public_key
    assert socket.assigns.event_contract == "dual"
    assert is_map(socket.assigns.client_meta)
    assert socket.assigns.peer_ip == "127.0.0.1"
    assert {:ok, "127.0.0.1"} = QuicdialRegistry.resolve(public_key)
  end

  test "connect captures ipv6 peer addresses from peer_data" do
    public_key = "alice_pub_key_ipv6"

    assert {:ok, socket} =
             connect(
               SankakuSocket,
               %{"public_key" => public_key},
               connect_info: %{peer_data: %{address: {0, 0, 0, 0, 0, 0, 0, 1}, port: 45_002}}
             )

    assert is_binary(socket.assigns.peer_ip)
    assert String.contains?(socket.assigns.peer_ip, ":")
    assert {:ok, resolved_ip} = QuicdialRegistry.resolve(public_key)
    assert resolved_ip == socket.assigns.peer_ip
  end

  test "connect rejects missing public_key" do
    assert :error = connect(SankakuSocket, %{})
  end

  test "join rejects mismatched peer topic" do
    assert {:ok, socket} = connect(SankakuSocket, %{"public_key" => "alice_pub_key_join"})

    assert {:error, %{reason: "unauthorized_join"}} =
             subscribe_and_join(socket, SignalingChannel, "peer:bob_pub_key")
  end
end
