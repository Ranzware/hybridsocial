defmodule Hybridsocial.Media.MediaProxyCacheWorker do
  @moduledoc """
  Hourly cleanup tick for the media proxy cache.

  On every tick:
    1. Drop entries whose `last_accessed_at` is older than the
       configured TTL (default 7 days).
    2. If total cache size still exceeds the configured cap
       (default 5 GB), drop oldest-accessed entries until under.

  Both eviction passes are best-effort — failures are logged but
  don't crash the worker. If the cache layer is disabled in
  config, the tick just no-ops.
  """
  use GenServer

  alias Hybridsocial.Media.MediaProxyCache

  require Logger

  @interval :timer.hours(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    if MediaProxyCache.enabled?() do
      run_eviction()
    end

    schedule_tick()
    {:noreply, state}
  end

  defp run_eviction do
    case MediaProxyCache.evict_expired() do
      {:ok, n} when n > 0 ->
        Logger.info("MediaProxyCacheWorker: evicted #{n} expired entries")

      _ ->
        :ok
    end

    case MediaProxyCache.evict_lru() do
      {:ok, n} when n > 0 ->
        Logger.info("MediaProxyCacheWorker: evicted #{n} LRU entries to fit cap")

      _ ->
        :ok
    end
  rescue
    e ->
      Logger.error("MediaProxyCacheWorker crashed: #{Exception.message(e)}")
      :ok
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @interval)
end
