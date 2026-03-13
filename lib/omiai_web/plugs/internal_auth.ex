defmodule OmiaiWeb.Plugs.InternalAuth do
  @moduledoc """
  Plug that verifies requests from the internal Python backend
  using a shared API key in the Authorization header.

  Expected header: `Authorization: Bearer <OMIAI_INTERNAL_API_KEY>`
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    expected_key = Application.get_env(:omiai, :internal_api_key)

    if is_nil(expected_key) or expected_key == "" do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(503, Jason.encode!(%{error: "internal_api_key_not_configured"}))
      |> halt()
    else
      case get_req_header(conn, "authorization") do
        ["Bearer " <> key] when key == expected_key ->
          conn

        _ ->
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
          |> halt()
      end
    end
  end
end
