defmodule Hybridsocial.Metrics.Probes.Postgres do
  @moduledoc """
  Builds a sample list for the running Postgres database. Counter-style
  values (commits, slow queries) are converted to per-second rates by
  the collector; this module only emits the raw counter so the
  collector can diff against the prior tick.
  """

  alias Hybridsocial.Repo

  @doc """
  Returns `{:ok, samples}` where samples is a list of
  `{metric, value, kind}` tuples. `kind` is `:gauge` (use as-is) or
  `:counter` (the collector diffs against last tick).
  """
  def sample do
    try do
      with {:ok, conns} <- pg_connections(),
           {:ok, db_size} <- pg_db_size(),
           {:ok, xact} <- pg_xact_commit(),
           {:ok, hit_ratio} <- pg_cache_hit_ratio() do
        samples = [
          {"connections_active", conns.active, :gauge},
          {"connections_idle", conns.idle, :gauge},
          {"db_size_bytes", db_size, :gauge},
          {"xact_commit", xact, :counter},
          {"cache_hit_ratio", hit_ratio, :gauge}
        ]

        {:ok, samples}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp pg_connections do
    %Postgrex.Result{rows: [[active, idle]]} =
      Repo.query!("""
      SELECT
        count(*) FILTER (WHERE state = 'active'),
        count(*) FILTER (WHERE state = 'idle')
      FROM pg_stat_activity
      WHERE pid <> pg_backend_pid()
      """)

    {:ok, %{active: active || 0, idle: idle || 0}}
  end

  defp pg_db_size do
    %Postgrex.Result{rows: [[size]]} =
      Repo.query!("SELECT pg_database_size(current_database())")

    {:ok, size || 0}
  end

  defp pg_xact_commit do
    %Postgrex.Result{rows: [[xact]]} =
      Repo.query!("""
      SELECT COALESCE(SUM(xact_commit), 0)::bigint
      FROM pg_stat_database
      WHERE datname = current_database()
      """)

    {:ok, xact || 0}
  end

  defp pg_cache_hit_ratio do
    %Postgrex.Result{rows: [[hit, read]]} =
      Repo.query!("""
      SELECT COALESCE(SUM(blks_hit), 0)::bigint, COALESCE(SUM(blks_read), 0)::bigint
      FROM pg_stat_database
      WHERE datname = current_database()
      """)

    total = (hit || 0) + (read || 0)
    ratio = if total > 0, do: (hit || 0) / total, else: 1.0
    {:ok, ratio}
  end
end
