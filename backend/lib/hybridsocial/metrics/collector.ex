defmodule Hybridsocial.Metrics.Collector do
  @moduledoc """
  Polls every backing service every 60s and writes one batch of
  samples. Counter-style metrics (xact_commit, in_msgs, evicted_keys)
  are stored as **per-second rates** computed from the prior tick's
  raw value, held in this GenServer's state. That makes the rate
  charts trivial to render — no client-side diffing, no off-by-one
  on row gaps.

  A failed probe records nothing for that service that tick — better
  than zeros, which would draw a flatline that looks like real data.
  Charts will simply show a gap.
  """

  use GenServer
  require Logger

  alias Hybridsocial.Repo
  alias Hybridsocial.Metrics.Probes

  @tick_ms 60_000

  @services %{
    "postgres" => Probes.Postgres,
    "valkey" => Probes.Valkey,
    "nats" => Probes.Nats,
    "opensearch" => Probes.Opensearch
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Wait one tick before the first probe so all of the supervised
    # backends (Repo, Valkey pool, Nats) have a chance to come up.
    schedule_tick()
    {:ok, %{counters: %{}}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule_tick()
    new_state = run_tick(state)
    {:noreply, new_state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp run_tick(state) do
    now = DateTime.utc_now()

    # Probes run in parallel — a slow one shouldn't push the others
    # past the next tick. Each yields {service, result}.
    results =
      @services
      |> Map.to_list()
      |> Task.async_stream(
        fn {service, mod} -> {service, mod.sample()} end,
        timeout: 10_000,
        on_timeout: :kill_task,
        ordered: false
      )
      |> Enum.map(fn
        {:ok, pair} -> pair
        {:exit, _} -> {nil, {:error, "probe timeout"}}
      end)
      |> Enum.reject(fn {service, _} -> is_nil(service) end)

    {rows, new_counters} =
      Enum.reduce(results, {[], state.counters}, fn {service, result}, {acc_rows, acc_counters} ->
        case result do
          {:ok, samples} ->
            {sample_rows, updated_counters} =
              Enum.reduce(samples, {[], acc_counters}, fn {metric, raw, kind}, {r, c} ->
                case resolve_value(kind, service, metric, raw, c) do
                  {:emit, value, c2} ->
                    {[
                       %{
                         service: service,
                         metric: metric,
                         value: value * 1.0,
                         inserted_at: now
                       }
                       | r
                     ], c2}

                  {:skip, c2} ->
                    {r, c2}
                end
              end)

            {acc_rows ++ sample_rows, updated_counters}

          {:skip, _reason} ->
            {acc_rows, acc_counters}

          {:error, reason} ->
            Logger.warning("metrics collector: #{service} probe failed: #{inspect(reason)}")
            {acc_rows, acc_counters}
        end
      end)

    case rows do
      [] ->
        :ok

      rows ->
        case Repo.insert_all("service_metrics", rows) do
          {_count, _} -> :ok
        end
    end

    %{state | counters: new_counters}
  end

  # Gauges are stored verbatim. Counters are diffed against the prior
  # tick to produce a per-second rate; on the first observation we only
  # record the baseline (return {:skip, …}) so the first chart point
  # isn't a spike representing whatever the running total was at boot.
  defp resolve_value(:gauge, _service, _metric, raw, counters), do: {:emit, raw, counters}

  defp resolve_value(:counter, service, metric, raw, counters) do
    key = {service, metric}

    case Map.get(counters, key) do
      nil ->
        {:skip, Map.put(counters, key, raw)}

      prev ->
        delta = max(raw - prev, 0)
        rate = delta / (@tick_ms / 1000)
        {:emit, rate, Map.put(counters, key, raw)}
    end
  end
end
