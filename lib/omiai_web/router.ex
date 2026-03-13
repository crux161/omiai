defmodule OmiaiWeb.Router do
  use OmiaiWeb, :router

  import Phoenix.LiveDashboard.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :internal_auth do
    plug :accepts, ["json"]
    plug OmiaiWeb.Plugs.InternalAuth
  end

  # BasicAuth-protected pipeline for admin routes (LiveDashboard)
  pipeline :admin_auth do
    plug :accepts, ["html"]
    plug :basic_auth
  end

  # -------------------------------------------------------------------------
  # Internal webhook endpoints — called by the Python backend
  # -------------------------------------------------------------------------
  scope "/internal", OmiaiWeb do
    pipe_through :internal_auth

    post "/match_found", InternalController, :match_found
    post "/push_event", InternalController, :push_event
  end

  # -------------------------------------------------------------------------
  # Admin — LiveDashboard for observability (no Ecto repos)
  # -------------------------------------------------------------------------
  scope "/admin" do
    pipe_through :admin_auth

    live_dashboard "/metrics", metrics: OmiaiWeb.Telemetry
  end

  # -------------------------------------------------------------------------
  # BasicAuth plug — credentials from env vars or defaults in dev
  # -------------------------------------------------------------------------
  defp basic_auth(conn, _opts) do
    username = System.get_env("OMIAI_ADMIN_USER") || "admin"
    password = System.get_env("OMIAI_ADMIN_PASS") || "omiai"

    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end
end
