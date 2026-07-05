defmodule HybridsocialWeb.Plugs.TrustedProxies do
  @moduledoc """
  Resolves the real client IP from X-Forwarded-For, but ONLY when the
  direct TCP peer is itself a trusted proxy.

  Without this plug, any client can forge their IP by sending an
  `x-forwarded-for` header — bypassing IP bans, poisoning moderation
  logs, and shifting rate-limit buckets. `conn.remote_ip` is the raw
  TCP peer (set by Bandit/Plug); this plug overwrites it with the
  rightmost XFF entry that is NOT a trusted proxy, walking from the
  right. Hops to the right of that entry are trusted proxies and are
  accepted at face value.

  Configure trusted proxies via the `:trusted_proxies` app env as a
  list of CIDR strings:

      config :hybridsocial, :trusted_proxies, ["127.0.0.0/8", "10.0.0.0/8"]

  Default: `["127.0.0.0/8"]` (loopback only). In production behind a
  single Caddy/Nginx reverse proxy, set this to the proxy's IP range.
  """
  import Bitwise

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    peer = conn.remote_ip

    if trusted_proxy?(peer) do
      case xff_hops(conn) do
        nil ->
          conn

        hops ->
          case resolve_client_ip(hops) do
            nil -> conn
            ip -> %{conn | remote_ip: ip}
          end
      end
    else
      # Direct connection from a non-proxy — keep the real TCP peer.
      conn
    end
  end

  defp xff_hops(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [val | _] ->
        val
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      [] ->
        nil
    end
  end

  # Walk the XFF list from the right. The rightmost hop that is NOT a
  # trusted proxy is the real client IP. All hops to the right of it
  # are trusted proxies.
  defp resolve_client_ip(hops) do
    hops
    |> Enum.reverse()
    |> Enum.drop_while(&trusted_proxy_string?/1)
    |> List.first()
    |> case do
      nil -> nil
      ip_str -> parse_ip(ip_str)
    end
  end

  defp trusted_proxy_string?(str) do
    case parse_ip(str) do
      nil -> false
      ip -> trusted_proxy?(ip)
    end
  end

  defp parse_ip(str) do
    case :inet.parse_address(to_charlist(str)) do
      {:ok, ip} -> ip
      {:error, _} -> nil
    end
  end

  defp trusted_proxy?(ip) do
    trusted_proxies()
    |> Enum.any?(fn {net, prefix} -> ip_in_cidr?(ip, net, prefix) end)
  end

  defp trusted_proxies do
    Application.get_env(:hybridsocial, :trusted_proxies, ["127.0.0.0/8"])
    |> Enum.map(&parse_cidr/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_cidr(cidr) do
    case String.split(cidr, "/") do
      [ip_str, prefix_str] ->
        with {:ok, ip} <- :inet.parse_address(to_charlist(ip_str)),
             {prefix, ""} <- Integer.parse(prefix_str) do
          {ip, prefix}
        else
          _ -> nil
        end

      [ip_str] ->
        case :inet.parse_address(to_charlist(ip_str)) do
          {:ok, ip} -> {ip, full_prefix(ip)}
          {:error, _} -> nil
        end

      _ ->
        nil
    end
  end

  defp full_prefix({_, _, _, _}), do: 32
  defp full_prefix({_, _, _, _, _, _, _, _}), do: 128

  # IPv4 CIDR match
  defp ip_in_cidr?({a, b, c, d}, {na, nb, nc, nd}, prefix) do
    ip_int = (a <<< 24) ||| (b <<< 16) ||| (c <<< 8) ||| d
    net_int = (na <<< 24) ||| (nb <<< 16) ||| (nc <<< 8) ||| nd
    mask = if prefix == 0, do: 0, else: band(0xFFFFFFFF, bsl(0xFFFFFFFF, 32 - prefix))
    band(ip_int, mask) == band(net_int, mask)
  end

  # IPv6 CIDR match (two 64-bit halves)
  defp ip_in_cidr?({a, b, c, d, e, f, g, h}, {na, nb, nc, nd, ne, nf, ng, nh}, prefix) do
    ip_hi = (a <<< 48) ||| (b <<< 32) ||| (c <<< 16) ||| d
    ip_lo = (e <<< 48) ||| (f <<< 32) ||| (g <<< 16) ||| h
    net_hi = (na <<< 48) ||| (nb <<< 32) ||| (nc <<< 16) ||| nd
    net_lo = (ne <<< 48) ||| (nf <<< 32) ||| (ng <<< 16) ||| nh

    cond do
      prefix <= 0 ->
        true

      prefix >= 128 ->
        ip_hi == net_hi and ip_lo == net_lo

      prefix <= 64 ->
        mask = if prefix == 64, do: 0xFFFFFFFFFFFFFFFF, else: band(0xFFFFFFFFFFFFFFFF, bsl(0xFFFFFFFFFFFFFFFF, 64 - prefix))
        band(ip_hi, mask) == band(net_hi, mask)

      true ->
        lo_prefix = prefix - 64
        lo_mask = band(0xFFFFFFFFFFFFFFFF, bsl(0xFFFFFFFFFFFFFFFF, 64 - lo_prefix))
        ip_hi == net_hi and band(ip_lo, lo_mask) == band(net_lo, lo_mask)
    end
  end

  # Mismatched families — no match
  defp ip_in_cidr?(_, _, _), do: false
end
