defmodule Hybridsocial.Antivirus do
  @moduledoc """
  ClamAV scanner. Talks the `clamd` INSTREAM protocol over TCP — no
  shelling out, no temp files. Used by media upload to reject infected
  files before they hit storage.

  Disabled by default for dev; flip on via the `clamav_enabled` config
  flag once a `clamd` daemon is reachable. When disabled, `scan/1`
  returns `:ok` for every input so dev environments aren't held up by
  the absence of an antivirus daemon.

  Wire-format reference:
  https://docs.clamav.net/manual/Usage/Scanning.html#instream

      zINSTREAM\\0
      <chunk-length-be32><chunk-bytes>  (repeat)
      <0:32>                            (terminator)
      <- stream: OK\\0
      <- stream: <SIG> FOUND\\0
      <- stream: SIZE LIMIT EXCEEDED\\0  (or other error)
  """

  alias Hybridsocial.Config

  require Logger

  @chunk_size 65_536
  @default_timeout_ms 30_000

  @doc """
  Scans an in-memory binary. Returns:

    * `:ok` — clean (or scanning disabled)
    * `{:error, {:infected, signature_name}}` — a virus signature matched
    * `{:error, :unreachable}` — couldn't connect to clamd; we fail
      closed (reject the upload) rather than silently accept unscanned
      bytes when scanning is enabled.
    * `{:error, reason}` — other clamd / protocol error
  """
  def scan(binary) when is_binary(binary) do
    if enabled?() do
      do_scan(binary)
    else
      :ok
    end
  end

  @doc """
  Scans a file on disk by streaming its bytes to clamd in chunks.
  Same return contract as `scan/1`. Used by the media proxy so a
  large fetched body can be scanned without first holding it all
  in memory.
  """
  def scan_file(path) when is_binary(path) do
    if enabled?() do
      do_scan_file(path)
    else
      :ok
    end
  end

  @doc "Returns true when scanning is enabled in instance config."
  def enabled? do
    Config.get("clamav_enabled", false) == true
  end

  defp do_scan(binary) do
    host = Config.get("clamav_host", "clamav") |> to_charlist()
    port = Config.get("clamav_port", 3310)
    timeout = Config.get("clamav_timeout_ms", @default_timeout_ms)

    case :gen_tcp.connect(host, port, [:binary, active: false, packet: :raw], timeout) do
      {:ok, sock} ->
        try do
          send_instream(sock, binary, timeout)
        after
          :gen_tcp.close(sock)
        end

      {:error, reason} ->
        Logger.error("ClamAV: connection to #{host}:#{port} failed: #{inspect(reason)}")
        {:error, :unreachable}
    end
  end

  defp send_instream(sock, binary, timeout) do
    with :ok <- :gen_tcp.send(sock, "zINSTREAM\0"),
         :ok <- send_chunks(sock, binary),
         :ok <- :gen_tcp.send(sock, <<0::32>>),
         {:ok, raw} <- recv_response(sock, timeout) do
      parse_response(raw)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_scan_file(path) do
    host = Config.get("clamav_host", "clamav") |> to_charlist()
    port = Config.get("clamav_port", 3310)
    timeout = Config.get("clamav_timeout_ms", @default_timeout_ms)

    with {:ok, sock} <-
           :gen_tcp.connect(host, port, [:binary, active: false, packet: :raw], timeout),
         {:ok, file} <- File.open(path, [:read, :binary, :raw]) do
      try do
        with :ok <- :gen_tcp.send(sock, "zINSTREAM\0"),
             :ok <- stream_file_chunks(sock, file),
             :ok <- :gen_tcp.send(sock, <<0::32>>),
             {:ok, raw} <- recv_response(sock, timeout) do
          parse_response(raw)
        end
      after
        File.close(file)
        :gen_tcp.close(sock)
      end
    else
      {:error, reason} ->
        Logger.error("ClamAV: scan_file #{path} failed: #{inspect(reason)}")
        {:error, :unreachable}
    end
  end

  defp stream_file_chunks(sock, file) do
    case :file.read(file, @chunk_size) do
      :eof ->
        :ok

      {:ok, chunk} ->
        size = byte_size(chunk)

        case :gen_tcp.send(sock, <<size::32, chunk::binary>>) do
          :ok -> stream_file_chunks(sock, file)
          err -> err
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp send_chunks(_sock, <<>>), do: :ok

  defp send_chunks(sock, binary) when byte_size(binary) <= @chunk_size do
    size = byte_size(binary)
    :gen_tcp.send(sock, <<size::32, binary::binary>>)
  end

  defp send_chunks(sock, <<chunk::binary-size(@chunk_size), rest::binary>>) do
    case :gen_tcp.send(sock, <<@chunk_size::32, chunk::binary>>) do
      :ok -> send_chunks(sock, rest)
      err -> err
    end
  end

  defp recv_response(sock, timeout) do
    # clamd terminates the response with a NUL byte. Read until we
    # see one or the connection closes.
    do_recv(sock, "", timeout)
  end

  defp do_recv(sock, acc, timeout) do
    case :gen_tcp.recv(sock, 0, timeout) do
      {:ok, data} ->
        combined = acc <> data

        if String.contains?(combined, <<0>>) do
          {:ok, combined |> String.split(<<0>>) |> hd()}
        else
          do_recv(sock, combined, timeout)
        end

      {:error, :closed} when acc != "" ->
        {:ok, acc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response("stream: OK"), do: :ok

  defp parse_response("stream: " <> rest) do
    case String.split(rest, " ", trim: true) do
      [signature, "FOUND"] ->
        {:error, {:infected, signature}}

      _ ->
        if String.contains?(rest, "FOUND") do
          # Multi-word signatures fall back to whatever precedes "FOUND".
          [sig | _] = String.split(rest, " FOUND", parts: 2)
          {:error, {:infected, sig}}
        else
          {:error, {:clamd, rest}}
        end
    end
  end

  defp parse_response(other) do
    {:error, {:clamd, other}}
  end
end
