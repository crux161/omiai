defmodule OmiaiWeb.Plugs.Cors do
  @moduledoc """
  Simple CORS plug that handles preflight OPTIONS requests and adds
  the required Access-Control-* headers to every response.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{method: "OPTIONS"} = conn, _opts) do
    conn
    |> put_cors_headers()
    |> send_resp(204, "")
    |> halt()
  end

  def call(conn, _opts) do
    register_before_send(conn, fn conn -> put_cors_headers(conn) end)
  end

  defp put_cors_headers(conn) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "authorization, content-type, accept")
    |> put_resp_header("access-control-max-age", "86400")
  end
end
