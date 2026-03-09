defmodule OmiaiWeb.AdminAssets do
  @moduledoc """
  Plug that serves the bundled Phoenix + LiveView JS for the admin panel.
  Concatenates phoenix.min.js and phoenix_live_view.min.js at compile time,
  appending initialization code for the LiveSocket.
  """

  @behaviour Plug

  @phoenix_js File.read!(Application.app_dir(:phoenix, "priv/static/phoenix.js"))
  @live_view_js File.read!(Application.app_dir(:phoenix_live_view, "priv/static/phoenix_live_view.js"))

  @init_js """
  ;(function() {
    let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
    let liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
      params: { _csrf_token: csrfToken }
    });
    liveSocket.connect();
    window.liveSocket = liveSocket;
  })();
  """

  @bundle @phoenix_js <> "\n" <> @live_view_js <> "\n" <> @init_js
  @hash :crypto.hash(:md5, @bundle) |> Base.encode16(case: :lower) |> binary_part(0, 8)

  def js_path, do: "/admin/assets/admin.js?v=#{@hash}"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_content_type("application/javascript")
    |> Plug.Conn.put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> Plug.Conn.send_resp(200, @bundle)
    |> Plug.Conn.halt()
  end
end
