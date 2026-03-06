defmodule Omiai.Repo do
  use Ecto.Repo,
    otp_app: :omiai,
    adapter: Ecto.Adapters.SQLite3
end
