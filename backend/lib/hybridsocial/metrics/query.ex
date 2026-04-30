defmodule Hybridsocial.Metrics.Query do
  @moduledoc """
  Read API for stored service metrics. Supports raw "last N hours" reads
  and bucketed reads for longer windows so the dashboard payload stays
  small (a 30-day chart at 1-minute resolution would be 43k points; we
  bucket it to ~120 points instead).
  """

  import Ecto.Query

  alias Hybridsocial.Repo

  # window -> {duration_seconds, bucket_seconds | nil}
  # bucket=nil means "raw" — emit every row in the range.
  @windows %{
    "1h" => {3_600, nil},
    "6h" => {6 * 3_600, nil},
    "24h" => {24 * 3_600, 5 * 60},
    "7d" => {7 * 24 * 3_600, 60 * 60},
    "30d" => {30 * 24 * 3_600, 6 * 60 * 60}
  }

  @doc """
  Returns the latest sample for every (service, metric) pair plus a
  short 1-hour series for sparkline rendering. One DB call per series
  keeps the dashboard payload < 50KB.
  """
  def summary do
    cutoff_1h = DateTime.utc_now() |> DateTime.add(-3_600, :second)

    rows =
      Repo.all(
        from m in "service_metrics",
          where: m.inserted_at > ^cutoff_1h,
          order_by: [asc: m.service, asc: m.metric, asc: m.inserted_at],
          select: {m.service, m.metric, m.value, m.inserted_at}
      )

    rows
    |> Enum.group_by(fn {s, m, _, _} -> {s, m} end, fn {_, _, v, t} -> {t, v} end)
    |> Enum.map(fn {{service, metric}, points} ->
      latest = List.last(points)

      %{
        service: service,
        metric: metric,
        latest: %{t: elem(latest, 0), v: elem(latest, 1)},
        sparkline: Enum.map(points, fn {t, v} -> %{t: t, v: v} end)
      }
    end)
  end

  @doc """
  Returns a series for a single (service, metric) over the requested
  window. Buckets are computed in SQL via `date_bin` so the round-trip
  payload doesn't include thousands of rows we'd just collapse on the
  client.
  """
  def series(service, metric, window) when window in ["1h", "6h", "24h", "7d", "30d"] do
    {duration_s, bucket_s} = Map.fetch!(@windows, window)
    cutoff = DateTime.utc_now() |> DateTime.add(-duration_s, :second)

    samples =
      case bucket_s do
        nil ->
          Repo.all(
            from m in "service_metrics",
              where:
                m.service == ^service and
                  m.metric == ^metric and
                  m.inserted_at > ^cutoff,
              order_by: [asc: m.inserted_at],
              select: %{t: m.inserted_at, v: m.value}
          )

        seconds ->
          # `date_bin` is the right tool — it slots every row into a
          # fixed-width bucket relative to a reference timestamp,
          # which keeps the chart x-axis consistent regardless of
          # exactly when the collector ticks land.
          interval = "#{seconds} seconds"

          Repo.all(
            from m in "service_metrics",
              where:
                m.service == ^service and
                  m.metric == ^metric and
                  m.inserted_at > ^cutoff,
              group_by:
                fragment(
                  "date_bin(?::interval, ?, TIMESTAMP '2001-01-01')",
                  ^interval,
                  m.inserted_at
                ),
              order_by:
                fragment(
                  "date_bin(?::interval, ?, TIMESTAMP '2001-01-01')",
                  ^interval,
                  m.inserted_at
                ),
              select: %{
                t:
                  fragment(
                    "date_bin(?::interval, ?, TIMESTAMP '2001-01-01')",
                    ^interval,
                    m.inserted_at
                  ),
                v: avg(m.value)
              }
          )
      end

    %{service: service, metric: metric, window: window, samples: samples}
  end

  def series(_service, _metric, _window), do: {:error, :invalid_window}
end
