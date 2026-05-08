defmodule HybridsocialWeb.MediaProxyController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Antivirus
  alias Hybridsocial.Federation.InstancePolicy
  alias Hybridsocial.Media.Backends.Local
  alias Hybridsocial.Media.InfectedTracker
  alias Hybridsocial.Media.MediaProxy
  alias Hybridsocial.Media.MediaProxyCache
  alias Hybridsocial.Media.PlaceholderSvg
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

  # Hard caps for an upstream fetch.
  @fetch_timeout_ms 5_000
  @max_file_bytes 50_000_000

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
          |> serve_with_range(path)

        :miss ->
          serve_and_cache(conn, remote_url)
      end
    else
      {:error, reason} -> handle_error(conn, reason)
    end
  end

  # sobelow_skip ["Traversal.SendFile"]
  defp serve_and_cache(conn, remote_url) do
    # Stream the upstream body straight to a tmp file (no in-memory
    # buffering), AV-scan the file once, then promote it into the
    # cache and serve via send_file. From this point on every hit
    # for the URL skips both the network and the scanner.
    #
    # Safe send_file: cache_path is built by MediaProxyCache from a
    # SHA-256 of the verified remote URL — never user input.
    with {:ok, %{tmp_path: tmp_path, content_type: ct, byte_size: size}} <-
           stream_remote_to_tmp(remote_url),
         :ok <- scan_file_or_cleanup(tmp_path),
         content_type = sanitize_content_type(ct),
         {:ok, %{path: cache_path}} <-
           MediaProxyCache.store_path(remote_url, tmp_path, content_type, size) do
      conn
      |> put_response_headers(content_type)
      |> serve_with_range(cache_path)
    else
      {:error, reason} -> handle_error(conn, reason)
    end
  end

  # send_file/3 ignores Range headers — Plug.Static handles them but
  # we're outside that path. Parse the header ourselves so video
  # seeking works on cached entries (browsers issue Range on every
  # seek; without 206 they have to re-download from byte 0).
  # sobelow_skip ["Traversal.SendFile"]
  defp serve_with_range(conn, path) do
    conn = put_resp_header(conn, "accept-ranges", "bytes")

    case get_req_header(conn, "range") do
      [range] ->
        case File.stat(path) do
          {:ok, %File.Stat{size: file_size}} ->
            send_range_or_full(conn, path, range, file_size)

          {:error, _} ->
            send_file(conn, 200, path)
        end

      _ ->
        send_file(conn, 200, path)
    end
  end

  # sobelow_skip ["Traversal.SendFile"]
  defp send_range_or_full(conn, path, range, file_size) do
    with %{"bytes" => bytes} <- Plug.Conn.Utils.params(range),
         {range_start, range_end} <- parse_range(bytes, file_size) do
      length = range_end - range_start + 1

      conn
      |> put_resp_header("content-range", "bytes #{range_start}-#{range_end}/#{file_size}")
      |> send_file(206, path, range_start, length)
    else
      _ -> send_file(conn, 200, path)
    end
  end

  defp parse_range("-" <> rest, file_size) do
    case Integer.parse(rest) do
      {last, ""} when last > 0 and last <= file_size -> {file_size - last, file_size - 1}
      _ -> :error
    end
  end

  defp parse_range(range, file_size) do
    case Integer.parse(range) do
      {first, "-"} when first >= 0 and first < file_size ->
        {first, file_size - 1}

      {first, "-" <> rest} when first >= 0 and first < file_size ->
        case Integer.parse(rest) do
          {last, ""} when last >= first -> {first, min(last, file_size - 1)}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp stream_remote_to_tmp(url) do
    headers = [
      {"User-Agent", "HybridSocial MediaProxy/0.1.0"},
      {"Accept", "*/*"}
    ]

    opts = [
      stream_to: self(),
      async: :once,
      recv_timeout: @fetch_timeout_ms,
      timeout: @fetch_timeout_ms,
      follow_redirect: true,
      max_redirect: 3
    ]

    with {:ok, tmp_path} <- new_tmp_path(),
         {:ok, file} <- File.open(tmp_path, [:write, :binary, :raw]) do
      case HTTPoison.get(url, headers, opts) do
        {:ok, %HTTPoison.AsyncResponse{id: id}} ->
          result =
            recv_stream(id, file, tmp_path, %{
              status: nil,
              content_type: "application/octet-stream",
              size: 0
            })

          File.close(file)
          finalize_stream(result, tmp_path)

        {:error, %HTTPoison.Error{reason: reason}} ->
          File.close(file)
          File.rm(tmp_path)
          {:error, reason}
      end
    end
  end

  defp new_tmp_path do
    dir = Path.join([Local.uploads_dir(), "proxy_cache", ".tmp"])

    case File.mkdir_p(dir) do
      :ok ->
        name = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
        {:ok, Path.join(dir, name)}

      err ->
        err
    end
  end

  # On any error path the partial download is unusable — make sure
  # the tmp file doesn't leak even if the request blew up
  # mid-stream. tmp_path is built from random bytes inside our own
  # uploads dir (see new_tmp_path/0) so the File.rm is safe.
  # sobelow_skip ["Traversal.FileModule"]
  defp finalize_stream({:ok, _} = ok, _tmp_path), do: ok

  # sobelow_skip ["Traversal.FileModule"]
  defp finalize_stream({:error, _} = err, tmp_path) do
    File.rm(tmp_path)
    err
  end

  defp recv_stream(id, file, tmp_path, state) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: code} when code in 200..299 ->
        HTTPoison.stream_next(id)
        recv_stream(id, file, tmp_path, %{state | status: code})

      %HTTPoison.AsyncStatus{id: ^id, code: code} ->
        cancel_async(id)
        {:error, {:http_error, code}}

      %HTTPoison.AsyncHeaders{id: ^id, headers: headers} ->
        ct = header_value(headers, "content-type") || state.content_type
        HTTPoison.stream_next(id)
        recv_stream(id, file, tmp_path, %{state | content_type: ct})

      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
        new_size = state.size + byte_size(chunk)

        if new_size > @max_file_bytes do
          cancel_async(id)
          {:error, :too_large}
        else
          case IO.binwrite(file, chunk) do
            :ok ->
              HTTPoison.stream_next(id)
              recv_stream(id, file, tmp_path, %{state | size: new_size})

            err ->
              cancel_async(id)
              {:error, err}
          end
        end

      %HTTPoison.AsyncRedirect{id: ^id} ->
        # follow_redirect: true means hackney handles the actual
        # redirect for us — we just keep draining the new request.
        HTTPoison.stream_next(id)
        recv_stream(id, file, tmp_path, state)

      %HTTPoison.AsyncEnd{id: ^id} ->
        {:ok, %{tmp_path: tmp_path, content_type: state.content_type, byte_size: state.size}}

      %HTTPoison.Error{id: ^id, reason: reason} ->
        {:error, reason}
    after
      @fetch_timeout_ms ->
        cancel_async(id)
        {:error, :timeout}
    end
  end

  defp cancel_async(id) do
    # hackney exposes the cancel; ignore failures — we're already
    # on an error path and just want the socket released.
    try do
      :hackney.stop_async(id)
    catch
      _, _ -> :ok
    end
  end

  defp header_value(headers, name) do
    target = String.downcase(name)

    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(to_string(k)) == target, do: v
    end)
  end

  # tmp_path comes from new_tmp_path/0 (random bytes under
  # uploads_dir) — never user input. The File.rm calls below are
  # safe; suppressing sobelow's pattern-based traversal alarm.
  # sobelow_skip ["Traversal.FileModule"]
  defp scan_file_or_cleanup(tmp_path) do
    case Antivirus.scan_file(tmp_path) do
      :ok ->
        :ok

      {:error, {:infected, _signature_name}} = err ->
        # Bubble infection up: handle_error/2 logs, records audit
        # metadata, and renders the placeholder.
        File.rm(tmp_path)
        err

      {:error, :unreachable} ->
        File.rm(tmp_path)
        {:error, :av_unreachable}

      {:error, other} ->
        File.rm(tmp_path)
        {:error, {:av_error, other}}
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

  # Infected remote media: log, record for audit/trending (no
  # identity — it's a federated stranger, not one of our users), then
  # serve a friendly "content removed" SVG in place of the bytes.
  # Served as 200 image/svg+xml so <img> renders the placeholder
  # inline instead of showing a broken-image icon; a 4xx here would
  # look like the server itself failed.
  defp handle_error(conn, {:infected, signature_name}) do
    Logger.warning("Media proxy refused infected payload signature=#{signature_name}")
    InfectedTracker.record(nil, signature_name, "proxy", 0)
    send_placeholder(conn, PlaceholderSvg.infected())
  end

  # Scanner down: fail-closed at the byte level, but still render a
  # recognisable placeholder so the consumer's UI doesn't look broken.
  defp handle_error(conn, :av_unreachable) do
    Logger.warning("Media proxy refused payload — antivirus scanner unreachable")
    send_placeholder(conn, PlaceholderSvg.scanner_unreachable())
  end

  defp handle_error(conn, {:av_error, inner}) do
    Logger.warning("Media proxy refused payload — antivirus error: #{inspect(inner)}")
    send_placeholder(conn, PlaceholderSvg.scanner_unreachable())
  end

  defp handle_error(conn, :too_large) do
    # Upstream sent more than @max_file_bytes — bail out rather
    # than fill the cache with one giant blob.
    conn |> put_status(413) |> json(%{error: "Remote media exceeds size limit"})
  end

  defp handle_error(conn, :timeout) do
    conn |> put_status(504) |> json(%{error: "Remote media fetch timed out"})
  end

  defp handle_error(conn, reason) do
    Logger.warning("Media proxy fetch failed: #{inspect(reason)}")
    conn |> put_status(502) |> json(%{error: "Failed to fetch remote media"})
  end

  # sobelow_skip ["XSS.SendResp"]
  defp send_placeholder(conn, svg) do
    # Safe: the SVG body is produced entirely by PlaceholderSvg which
    # escapes every interpolation. No user input reaches the body.
    conn
    |> put_resp_header("content-type", "image/svg+xml; charset=utf-8")
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("content-security-policy", "default-src 'none'")
    |> send_resp(200, svg)
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
