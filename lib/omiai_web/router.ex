defmodule OmiaiWeb.Router do
  use OmiaiWeb, :router

  import Phoenix.LiveDashboard.Router
  import Phoenix.LiveView.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug OmiaiWeb.Plugs.AuthToken
  end

  # BasicAuth-protected pipeline for admin routes (LiveDashboard, etc.)
  pipeline :admin_auth do
    plug :accepts, ["html"]
    plug :basic_auth
  end

  scope "/api", OmiaiWeb do
    pipe_through :api

    # Public routes
    post "/auth/signup", AuthController, :signup
    post "/auth/login", AuthController, :login
    post "/auth/request-password-reset", AuthController, :request_password_reset
    post "/auth/reset-password", AuthController, :reset_password
  end

  scope "/api", OmiaiWeb do
    pipe_through [:api, :require_auth]

    # Authenticated routes
    get "/auth/me", AuthController, :me

    get "/profile", ProfileController, :show
    put "/profile", ProfileController, :update

    get "/friends", FriendsController, :index
    get "/friends/requests", FriendsController, :pending_requests
    post "/friends/request", FriendsController, :create_request
    post "/friends/:id/accept", FriendsController, :accept
    post "/friends/:id/decline", FriendsController, :decline
    delete "/friends/:quicdial_id", FriendsController, :remove
  end

  scope "/admin" do
    pipe_through :admin_auth

    get "/assets/admin.js", OmiaiWeb.AdminAssets, :js

    live_dashboard "/metrics",
      metrics: OmiaiWeb.Telemetry,
      ecto_repos: [Omiai.Repo]

    live_session :admin_users, root_layout: {OmiaiWeb.Layouts, :admin_root} do
      live "/users", OmiaiWeb.AdminLive.Users, :index
      live "/users/new", OmiaiWeb.AdminLive.Users, :new
      live "/users/:id/edit", OmiaiWeb.AdminLive.Users, :edit
      live "/users/:id/reset-password", OmiaiWeb.AdminLive.Users, :reset_password
    end
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
