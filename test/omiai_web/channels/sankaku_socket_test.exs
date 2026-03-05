defmodule OmiaiWeb.SankakuSocketTest do
  use ExUnit.Case, async: true
  import Phoenix.ChannelTest

  alias OmiaiWeb.{SankakuSocket, SignalingChannel}

  @endpoint OmiaiWeb.Endpoint

  test "connect accepts public_key and applies default contract" do
    assert {:ok, socket} = connect(SankakuSocket, %{"public_key" => "alice_pub_key"})

    assert socket.assigns.public_key == "alice_pub_key"
    assert socket.assigns.event_contract == "dual"
    assert is_map(socket.assigns.client_meta)
  end

  test "connect rejects missing public_key" do
    assert :error = connect(SankakuSocket, %{})
  end

  test "join rejects mismatched peer topic" do
    assert {:ok, socket} = connect(SankakuSocket, %{"public_key" => "alice_pub_key"})

    assert {:error, %{reason: "unauthorized_join"}} =
             subscribe_and_join(socket, SignalingChannel, "peer:bob_pub_key")
  end
end
