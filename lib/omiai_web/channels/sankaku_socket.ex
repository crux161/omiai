defmodule OmiaiWeb.SankakuSocket do
  use Phoenix.Socket

  require Logger

  alias OmiaiWeb.Auth.SocketAuth

  channel "peer:*", OmiaiWeb.SignalingChannel

  @impl true
  def connect(params, socket, connect_info) do
    case SocketAuth.authenticate(params, connect_info) do
      {:ok, claims} ->
        ip = claims.client_meta[:ip] || "unknown"

        Logger.info(
          "socket_connected public_key=#{claims.public_key} contract=#{claims.event_contract} ip=#{ip}"
        )

        authed_socket =
          socket
          |> assign(:public_key, claims.public_key)
          |> assign(:event_contract, claims.event_contract)
          |> assign(:client_meta, claims.client_meta)

        {:ok, authed_socket}

      {:error, reason} ->
        Logger.warning("socket_rejected reason=#{inspect(reason)}")
        :error
    end
  end

  @impl true
  def id(%Phoenix.Socket{assigns: %{public_key: public_key}}), do: "peer:" <> public_key
end
