defmodule Hybridsocial.Moderation.AppealExpiryWorker do
  @moduledoc """
  Periodically deletes approved / rejected appeals older than the
  configured retention window. Default: 90 days. Tunable at runtime
  via the `appeal_retention_days` instance setting.

  Pending appeals are never touched — they still need admin action.
  Runs hourly, with an initial tick on boot so a restart doesn't
  wait a full hour.
  """
  use GenServer

  alias Hybridsocial.{Config, Moderation}

  require Logger

  @interval :timer.hours(1)
  @default_retention_days 90

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    send(self(), :tick)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:tick, state) do
    case safely_prune() do
      n when n > 0 -> Logger.info("AppealExpiryWorker: pruned #{n} closed appeal(s)")
      _ -> :ok
    end

    Process.send_after(self(), :tick, @interval)
    {:noreply, state}
  end

  defp safely_prune do
    Moderation.prune_closed_appeals(retention_days())
  rescue
    e ->
      Logger.error("AppealExpiryWorker crashed: #{Exception.message(e)}")
      0
  end

  defp retention_days do
    case Config.get("appeal_retention_days", @default_retention_days) do
      n when is_integer(n) and n > 0 ->
        n

      n when is_binary(n) ->
        case Integer.parse(n) do
          {i, _} when i > 0 -> i
          _ -> @default_retention_days
        end

      _ ->
        @default_retention_days
    end
  end
end
