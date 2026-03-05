defmodule Omiai.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      OmiaiWeb.Telemetry,
      {Phoenix.PubSub, name: Omiai.PubSub},
      OmiaiWeb.QuicdialRegistry,
      OmiaiWeb.Presence,
      OmiaiWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Omiai.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    OmiaiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
