defmodule Hybridsocial.AntivirusTest do
  @moduledoc """
  Unit tests for the ClamAV INSTREAM scanner. We don't depend on a
  real `clamd` daemon — instead each test stands up a tiny TCP echo
  server that speaks just enough of the protocol to assert our
  framing + parsing.
  """
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Antivirus
  alias Hybridsocial.Config

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)
    :ok
  end

  describe "scan/1 when disabled" do
    test "returns :ok without contacting any daemon" do
      Config.set("clamav_enabled", false)
      # Even if there's no clamd anywhere, this must succeed.
      assert :ok = Antivirus.scan("anything")
    end
  end

  describe "scan/1 when enabled" do
    setup do
      port = start_fake_clamd(fn _binary -> "stream: OK" end)
      Config.set("clamav_enabled", true)
      Config.set("clamav_host", "127.0.0.1")
      Config.set("clamav_port", port)
      :ok
    end

    test "returns :ok when clamd reports clean" do
      assert :ok = Antivirus.scan("clean payload")
    end
  end

  describe "scan/1 when virus detected" do
    setup do
      port =
        start_fake_clamd(fn _binary -> "stream: Win.Test.EICAR_HDB-1 FOUND" end)

      Config.set("clamav_enabled", true)
      Config.set("clamav_host", "127.0.0.1")
      Config.set("clamav_port", port)
      :ok
    end

    test "returns {:error, {:infected, signature}}" do
      assert {:error, {:infected, "Win.Test.EICAR_HDB-1"}} =
               Antivirus.scan("malicious payload")
    end
  end

  describe "scan/1 when clamd is unreachable" do
    setup do
      Config.set("clamav_enabled", true)
      Config.set("clamav_host", "127.0.0.1")
      # Pick a port nothing is listening on
      Config.set("clamav_port", 1)
      :ok
    end

    test "fails closed with :unreachable" do
      assert {:error, :unreachable} = Antivirus.scan("anything")
    end
  end

  describe "scan_file/1" do
    test "returns :ok without contacting any daemon when disabled" do
      Config.set("clamav_enabled", false)
      tmp = write_tmp("anything")
      assert :ok = Antivirus.scan_file(tmp)
      File.rm(tmp)
    end

    test "streams a file's bytes to clamd and reports clean" do
      port = start_fake_clamd(fn _binary -> "stream: OK" end)
      Config.set("clamav_enabled", true)
      Config.set("clamav_host", "127.0.0.1")
      Config.set("clamav_port", port)

      tmp = write_tmp("clean payload")
      assert :ok = Antivirus.scan_file(tmp)
      File.rm(tmp)
    end

    test "reports infection when the daemon flags a signature" do
      port = start_fake_clamd(fn _binary -> "stream: Win.Test.EICAR_HDB-1 FOUND" end)
      Config.set("clamav_enabled", true)
      Config.set("clamav_host", "127.0.0.1")
      Config.set("clamav_port", port)

      tmp = write_tmp("eicar")
      assert {:error, {:infected, "Win.Test.EICAR_HDB-1"}} = Antivirus.scan_file(tmp)
      File.rm(tmp)
    end

    test "reassembles a multi-chunk file payload correctly" do
      port =
        start_fake_clamd(fn binary ->
          if byte_size(binary) == 200 * 1024,
            do: "stream: OK",
            else: "stream: SizeMismatch FOUND"
        end)

      Config.set("clamav_enabled", true)
      Config.set("clamav_host", "127.0.0.1")
      Config.set("clamav_port", port)

      tmp = write_tmp(:binary.copy(<<"x">>, 200 * 1024))
      assert :ok = Antivirus.scan_file(tmp)
      File.rm(tmp)
    end
  end

  describe "scan/1 with multi-chunk payloads" do
    setup do
      # 200KB → multiple INSTREAM chunks of 64KB
      port =
        start_fake_clamd(fn binary ->
          # Echo the size we received in the response so we can assert
          # the framing reassembled correctly.
          if byte_size(binary) == 200 * 1024 do
            "stream: OK"
          else
            "stream: SizeMismatch FOUND"
          end
        end)

      Config.set("clamav_enabled", true)
      Config.set("clamav_host", "127.0.0.1")
      Config.set("clamav_port", port)
      :ok
    end

    test "chunks correctly across the 64KB boundary" do
      payload = :binary.copy(<<"x">>, 200 * 1024)
      assert :ok = Antivirus.scan(payload)
    end
  end

  defp write_tmp(content) do
    name = Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
    path = Path.join(System.tmp_dir!(), "av_scan_test_#{name}")
    File.write!(path, content)
    path
  end

  # ---- Fake clamd helpers ------------------------------------------------

  # Spawns a one-shot TCP listener on an ephemeral port that:
  # 1. expects the literal "zINSTREAM\0"
  # 2. reads INSTREAM chunks (length-prefixed) until the 4-byte zero terminator
  # 3. calls `respond_fn` with the reassembled binary to get the response string
  # 4. sends the response + NUL terminator and closes
  defp start_fake_clamd(respond_fn) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])

    {:ok, port} = :inet.port(listener)

    spawn_link(fn ->
      {:ok, sock} = :gen_tcp.accept(listener)

      try do
        {:ok, prefix} = :gen_tcp.recv(sock, byte_size("zINSTREAM\0"))

        if prefix != "zINSTREAM\0" do
          :gen_tcp.send(sock, "stream: BadHandshake FOUND\0")
        else
          binary = read_chunks(sock, "")
          :gen_tcp.send(sock, respond_fn.(binary) <> <<0>>)
        end
      after
        :gen_tcp.close(sock)
        :gen_tcp.close(listener)
      end
    end)

    port
  end

  defp read_chunks(sock, acc) do
    case :gen_tcp.recv(sock, 4) do
      {:ok, <<0::32>>} ->
        acc

      {:ok, <<size::32>>} ->
        {:ok, chunk} = :gen_tcp.recv(sock, size)
        read_chunks(sock, acc <> chunk)

      {:error, _} ->
        acc
    end
  end
end
