defmodule Omiai.MdnsBroadcaster do
  @moduledoc """
  Publishes this Omiai node over mDNS so local clients can discover
  `_omiai._tcp` automatically.
  """

  use GenServer

  require Logger

  @service_id :omiai_signaling
  @service_type "_omiai._tcp"
  @instance_name "Omiai_Local_Node"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    send(self(), :register_mdns)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:register_mdns, state) do
    port = endpoint_port()

    case register_mdns_service(port) do
      :ok ->
        Logger.info(
          "omiai_mdns_registered type=#{@service_type} instance=#{@instance_name} port=#{port}"
        )

      {:error, reason} ->
        Logger.warning("omiai_mdns_registration_failed reason=#{inspect(reason)}")
    end

    {:noreply, state}
  end

  defp register_mdns_service(port) do
    with :ok <- ensure_mdns_started(),
         :ok <- MdnsLite.set_hosts([:hostname]),
         :ok <- MdnsLite.set_instance_name(@instance_name),
         :ok <- MdnsLite.add_mdns_service(service_payload(port)) do
      :ok
    else
      {:error, {:service_exists, @service_id}} -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp ensure_mdns_started do
    case Application.ensure_all_started(:mdns_lite) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :mdns_lite}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp endpoint_port do
    endpoint_config = Application.get_env(:omiai, OmiaiWeb.Endpoint, [])

    case Keyword.get(endpoint_config, :http, []) do
      opts when is_list(opts) ->
        case Keyword.get(opts, :port, 4000) do
          port when is_integer(port) and port > 0 ->
            port

          port when is_binary(port) ->
            case Integer.parse(port) do
              {parsed, _} when parsed > 0 -> parsed
              _ -> 4000
            end

          _ ->
            4000
        end

      _ ->
        4000
    end
  end

  defp service_payload(port) do
    %{
      id: @service_id,
      type: @service_type,
      port: port,
      instance_name: @instance_name,
      txt_payload: %{
        "service" => "omiai",
        "path" => "/ws/sankaku/websocket"
      }
    }
  end
end
