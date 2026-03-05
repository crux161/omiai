defmodule OmiaiWeb.Presence do
  use Phoenix.Presence,
    otp_app: :omiai,
    pubsub_server: Omiai.PubSub
end
