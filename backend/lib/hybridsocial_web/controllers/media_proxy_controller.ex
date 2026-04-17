defmodule HybridsocialWeb.MediaProxyController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Antivirus
  alias Hybridsocial.Federation.InstancePolicy
  alias Hybridsocial.Media.MediaProxy
  alias Hybridsocial.Media.MediaProxyCache
  alias Hybridsocial.Repo

  require Logger

  # Only allow media MIME types through the proxy. A compromised or hostile
  # upstream cannot trick the browser into rendering text/html as an HTML
  # page even if it omits nosniff; anything off-allowlist is forced to
  # application/octet-stream.
  @safe_media_prefixes ["image/", "video/", "audio/"]

  # Domains under one of these policies have their media refused
  # outright. `silence` and `force_nsfw` deliberately don't block —
  # they're about visibility, not security.
  @blocking_policies ~w(suspend block_media)

  @doc "Proxy a remote media URL through the local server."
  # sobelow_skip ["XSS.SendResp", "Traversal.SendFile"]
  def show(conn, %{"signature" => signature, "encoded_url" => encoded_url}) do
    with {:ok, remote_url} <- MediaProxy.verify_url(signature, encoded_url),
         :ok <- validate_remote_url(remote_url),
         :ok <- check_instance_policy(remote_url) do
      case MediaProxyCache.lookup(remote_url) do
        {:hit, %{path: path, content_type: content_type, hash: hash}} ->
          # Bump LRU bookkeeping but don't block the response on the
          # write — touch failures are harmless (just costs us a
          # re-fetch later if eviction comes for it before we
          # rewrite the timestamp).
          Task.start(fn -> MediaProxyCache.touch(hash) end)

          conn
          |> put_response_headers(sanitize_content_type(content_type))
          |> send_file(200, path)

        :miss ->
          serve_and_cache(conn, remote_url)
      end
    else
      {:error, reason} -> handle_error(conn, reason)
    end
  end

  defp serve_and_cache(conn, remote_url) do
    with {:ok, response} <- fetch_remote(remote_url),
         :ok <- scan_for_malware(response.body) do
      content_type = sanitize_content_type(get_content_type(response))
      # Best-effort write — if the disk fills up or the cache layer
      # is disabled, we still serve the bytes we already have.
      MediaProxyCache.store(remote_url, response.body, content_type)

      conn
      |> put_response_headers(content_type)
      |> send_resp(200, response.body)
    else
      {:error, reason} -> handle_error(conn, reason)
    end
  end

  defp put_response_headers(conn, content_type) do
    conn
    |> put_resp_header("content-type", content_type)
    |> put_resp_header("cache-control", "public, max-age=86400, immutable")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("content-security-policy", "default-src 'none'")
  end

  defp handle_error(conn, :invalid_signature),
    do: conn |> put_status(403) |> json(%{error: "Invalid signature"})

  defp handle_error(conn, :invalid_url),
    do: conn |> put_status(400) |> json(%{error: "Invalid URL"})

  defp handle_error(conn, :private_host),
    do: conn |> put_status(403) |> json(%{error: "Forbidden"})

  defp handle_error(conn, :instance_blocked),
    do: conn |> put_status(403) |> json(%{error: "Origin instance is blocked"})

  defp handle_error(conn, {:infected, signature_name}) do
    Logger.warning("Media proxy refused infected payload signature=#{signature_name}")
    conn |> put_status(403) |> json(%{error: "Content rejected by antivirus scan"})
  end

  defp handle_error(conn, reason) do
    Logger.warning("Media proxy fetch failed: #{inspect(reason)}")
    conn |> put_status(502) |> json(%{error: "Failed to fetch remote media"})
  end

  # Refuse to proxy from instances we've explicitly suspended or
  # block-media'd. Other policies (silence, force_nsfw) are about
  # visibility, not the bytes themselves, so the proxy still serves
  # those — they're handled at the timeline + UI layer.
  defp check_instance_policy(url) do
    domain = URI.parse(url).host

    if is_binary(domain) do
      case Repo.get(InstancePolicy, domain) do
        %InstancePolicy{policy: policy} when policy in @blocking_policies ->
          {:error, :instance_blocked}

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  # Stream the fetched body through ClamAV when scanning is enabled.
  # When disabled (dev environments without a clamd daemon), the
  # scanner returns :ok and we pass the body through unchanged.
  defp scan_for_malware(body) when is_binary(body) do
    case Antivirus.scan(body) do
      :ok -> :ok
      {:error, {:infected, _} = err} -> {:error, err}
      # If clamd is unreachable but scanning is enabled, fail closed —
      # we'd rather 502 than ship potentially-infected bytes to the
      # user's browser.
      {:error, :unreachable} -> {:error, :av_unreachable}
      {:error, other} -> {:error, {:av_error, other}}
    end
  end

  defp validate_remote_url(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, :invalid_url}

      is_nil(uri.host) or uri.host == "" ->
        {:error, :invalid_url}

      private_host?(uri.host) ->
        {:error, :private_host}

      true ->
        :ok
    end
  end

  defp fetch_remote(url) do
    headers = [
      {"User-Agent", "HybridSocial MediaProxy/0.1.0"},
      {"Accept", "*/*"}
    ]

    case HTTPoison.get(url, headers,
           timeout: 15_000,
           recv_timeout: 15_000,
           max_body_length: 50_000_000,
           follow_redirect: true
         ) do
      {:ok, %{status_code: 200} = response} ->
        {:ok, response}

      {:ok, %{status_code: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_content_type(%{headers: headers}) do
    headers
    |> Enum.find(fn {k, _v} -> String.downcase(k) == "content-type" end)
    |> case do
      {_, content_type} -> content_type
      nil -> "application/octet-stream"
    end
  end

  defp sanitize_content_type(content_type) when is_binary(content_type) do
    base = content_type |> String.split(";", parts: 2) |> hd() |> String.downcase()

    if Enum.any?(@safe_media_prefixes, &String.starts_with?(base, &1)) do
      base
    else
      "application/octet-stream"
    end
  end

  defp sanitize_content_type(_), do: "application/octet-stream"

  defp private_host?(host) do
    host in ["localhost", "127.0.0.1", "::1", "0.0.0.0"] or
      String.starts_with?(host, "10.") or
      String.starts_with?(host, "192.168.") or
      Regex.match?(~r/^172\.(1[6-9]|2[0-9]|3[01])\./, host)
  end
end
