defmodule HybridsocialWeb.Plugs.FederationRateLimiter do
  @moduledoc """
  Rate limiter for ActivityPub federation endpoints.

  Federation traffic has a fundamentally different shape than browser API
  traffic: a remote Mastodon/Akkoma/PeerTube instance may fan out tens of
  GETs in a few seconds while verifying a single signed activity (fetch
  actor + key, dereference object, walk outbox sample). The general-purpose
  anonymous limit (~240/min) starves these legitimate peers and produces
  silent federation failures — remotes report "Unable to fetch key JSON"
  or "Invalid HTTP Signature" because we 429'd their key fetch.

  This plug uses its own Valkey namespace (`fedrl:`) so federation counters
  do not collide with browser API counters from the same IP, and a higher
  ceiling configured via `Config.rate_limit_federation/0`.

  Identifies callers by IP. We don't try to parse the Signature header's
  keyId for the bucket key — many federation requests are unsigned GETs
  (to fetch the very key that would let us identify them), so per-IP is
  the only universally available signal. The much higher limit + isolated
  namespace makes IP-collision in NAT'd peers a non-issue in practice.

  Fail-open if Valkey is unavailable — same posture as the general rate
  limiter, so a cache outage doesn't break federation.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Hybridsocial.Cache
  alias Hybridsocial.Config

  @window_seconds 60

  def init(opts), do: opts

  def call(conn, _opts) do
    if enabled?() do
      identifier = ip_identifier(conn)
      limit = Config.rate_limit_federation()
      window = current_window()

      case check_rate(identifier, window, limit) do
        :ok ->
          conn

        {:error, retry_after} ->
          conn
          |> put_resp_header("retry-after", Integer.to_string(retry_after))
          |> put_status(:too_many_requests)
          |> json(%{
            error: "rate_limit.exceeded",
            message: "Federation rate limit exceeded. Try again later."
          })
          |> halt()
      end
    else
      conn
    end
  end

  defp enabled? do
    Application.get_env(:hybridsocial, :rate_limiting_enabled, true)
  end

  defp ip_identifier(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp current_window do
    div(System.system_time(:second), @window_seconds)
  end

  defp check_rate(identifier, window, limit) do
    key = "fedrl:#{identifier}:#{window}"

    case Cache.increment(key, @window_seconds + 60) do
      {:ok, count} when count > limit ->
        retry_after = @window_seconds - rem(System.system_time(:second), @window_seconds)
        {:error, max(retry_after, 1)}

      {:ok, _count} ->
        :ok

      {:error, _} ->
        :ok
    end
  end
end
