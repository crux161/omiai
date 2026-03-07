defmodule OmiaiWeb.Router do
  use OmiaiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :require_auth do
    plug OmiaiWeb.Plugs.AuthToken
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
end
