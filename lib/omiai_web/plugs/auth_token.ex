defmodule OmiaiWeb.Plugs.AuthToken do
  @moduledoc """
  Plug that extracts and verifies a Bearer JWT from the Authorization header.
  On success, assigns `:current_user_id` and `:current_quicdial_id` to `conn.assigns`.
  """

  @behaviour Plug

  import Plug.Conn

  alias OmiaiWeb.Auth.JwtToken

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- JwtToken.verify_token(token) do
      conn
      |> assign(:current_user_id, claims["sub"])
      |> assign(:current_quicdial_id, claims["quicdial_id"])
      |> assign(:current_display_name, claims["display_name"])
      |> assign(:current_avatar_id, claims["avatar_id"])
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end
end
