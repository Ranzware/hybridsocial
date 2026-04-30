defmodule Hybridsocial.Metrics.Probes.Nats do
  @moduledoc """
  NATS exposes a JSON monitoring endpoint on a separate HTTP port (8222
  by default). We hit the small `/varz`, `/connz`, and `/jsz`
  endpoints; each returns plenty without needing to fan out across
  per-connection or per-stream pages.
  """

  def sample do
    base_url = nats_monitor_url()

    try do
      with {:ok, varz} <- fetch_json(base_url <> "/varz"),
           {:ok, connz} <- fetch_json(base_url <> "/connz"),
           {:ok, jsz} <- fetch_json(base_url <> "/jsz") do
        samples = [
          {"connections", get_int(connz, "num_connections"), :gauge},
          {"in_msgs", get_int(varz, "in_msgs"), :counter},
          {"out_msgs", get_int(varz, "out_msgs"), :counter},
          {"jetstream_messages", get_int(jsz, "messages"), :gauge},
          {"jetstream_bytes", get_int(jsz, "bytes"), :gauge}
        ]

        {:ok, samples}
      else
        {:error, reason} -> {:error, reason}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp nats_monitor_url do
    Application.get_env(:hybridsocial, :nats_monitor_url, "http://hs_nats:8222")
  end

  defp fetch_json(url) do
    case :httpc.request(:get, {String.to_charlist(url), []}, [{:timeout, 3000}], []) do
      {:ok, {{_, 200, _}, _, body}} ->
        case Jason.decode(IO.iodata_to_binary(body)) do
          {:ok, json} -> {:ok, json}
          {:error, _} -> {:error, "invalid json"}
        end

      _ ->
        {:error, "nats monitor unreachable"}
    end
  end

  defp get_int(map, key) when is_map(map) do
    case Map.get(map, key) do
      n when is_integer(n) -> n
      n when is_float(n) -> trunc(n)
      _ -> 0
    end
  end
end
