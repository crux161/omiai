defmodule OmiaiWeb.Router do
  use OmiaiWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", OmiaiWeb do
    pipe_through :api
  end
end
