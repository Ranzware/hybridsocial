defmodule Hybridsocial.Metrics.Probes.Valkey do
  @moduledoc """
  Pulls samples from the Valkey/Redis INFO blocks. Counter-style metrics
  (`evicted_keys`, `total_commands_processed`) come back raw and the
  collector turns them into per-second rates. `instantaneous_ops_per_sec`
  is already a rate so we send it as a gauge.
  """

  def sample do
    try do
      with {:ok, "PONG"} <- Redix.command(:valkey_0, ["PING"]),
           {:ok, memory} <- Redix.command(:valkey_0, ["INFO", "memory"]),
           {:ok, clients} <- Redix.command(:valkey_0, ["INFO", "clients"]),
           {:ok, stats} <- Redix.command(:valkey_0, ["INFO", "stats"]),
           {:ok, db_size} <- Redix.command(:valkey_0, ["DBSIZE"]) do
        samples = [
          {"memory_used_bytes", parse_int(memory, "used_memory"), :gauge},
          {"memory_peak_bytes", parse_int(memory, "used_memory_peak"), :gauge},
          {"total_keys", db_size || 0, :gauge},
          {"connected_clients", parse_int(clients, "connected_clients"), :gauge},
          {"ops_per_sec", parse_int(stats, "instantaneous_ops_per_sec"), :gauge},
          {"evicted_keys", parse_int(stats, "evicted_keys"), :counter}
        ]

        {:ok, samples}
      else
        _ -> {:error, "valkey unreachable"}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp parse_int(info, field) do
    info
    |> String.split("\r\n")
    |> Enum.find_value(0, fn line ->
      case String.split(line, ":", parts: 2) do
        [^field, val] ->
          case Integer.parse(String.trim(val)) do
            {n, _} -> n
            :error -> 0
          end

        _ ->
          nil
      end
    end)
  end
end
