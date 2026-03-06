defmodule OmiaiWeb.Plugs.AuthToken do
  @moduledoc """
  Plug that extracts and verifies a Bearer token from the Authorization header.
  On success, assigns `:current_user` to `conn.assigns`.
  """

  @behaviour Plug

  import Plug.Conn

  alias Omiai.Accounts

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{user_id: user_id}} <- Accounts.verify_session_token(token) do
      user = Accounts.get_user!(user_id)
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end
end
