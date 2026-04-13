defmodule Hybridsocial.Social.StoryExpiryWorker do
  @moduledoc """
  Periodically hard-deletes expired stories (and their media files).
  Runs every 5 minutes.
  """
  use GenServer

  alias Hybridsocial.Social.Stories

  require Logger

  @interval :timer.minutes(5)

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
    case safely_delete() do
      n when n > 0 -> Logger.info("StoryExpiryWorker: hard-deleted #{n} expired stories")
      _ -> :ok
    end

    schedule_tick()
    {:noreply, state}
  end

  defp safely_delete do
    Stories.delete_expired()
  rescue
    e ->
      Logger.error("StoryExpiryWorker crashed: #{Exception.message(e)}")
      0
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @interval)
end
