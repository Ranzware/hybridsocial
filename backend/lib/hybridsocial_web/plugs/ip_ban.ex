defmodule HybridsocialWeb.Plugs.IpBan do
  @moduledoc """
  Plug that checks if the client's IP address is banned.
  Returns 403 with `{error: "ip_banned"}` if the IP matches any active ban,
  including CIDR range matches.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    ip = get_client_ip(conn)

    if Hybridsocial.Moderation.ip_banned?(ip) do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "ip_banned"})
      |> halt()
    else
      conn
    end
  end

  defp get_client_ip(conn) do
    # TrustedProxies plug (in the endpoint) already resolved the real
    # client IP into conn.remote_ip — use it directly, never the raw
    # XFF header which is client-spoofable.
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end
end
