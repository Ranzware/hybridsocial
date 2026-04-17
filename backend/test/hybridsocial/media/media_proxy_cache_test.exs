defmodule Hybridsocial.Media.MediaProxyCacheTest do
  @moduledoc """
  Tests for the disk-backed LRU cache layer in front of the media
  proxy. Each test starts the Config.Store + a temp uploads_dir so
  files don't collide across runs.
  """
  use Hybridsocial.DataCase, async: false
  import Ecto.Query

  alias Hybridsocial.Config
  alias Hybridsocial.Media.MediaProxyCache
  alias Hybridsocial.Repo

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)

    tmp =
      Path.join(System.tmp_dir!(), "hs_proxy_cache_test_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    System.put_env("UPLOADS_DIR", tmp)

    on_exit(fn ->
      System.delete_env("UPLOADS_DIR")
      File.rm_rf!(tmp)
    end)

    Config.set("media_proxy_cache_enabled", true)
    {:ok, tmp_dir: tmp}
  end

  describe "store/3 + lookup/1 round-trip" do
    test "stores bytes on disk and returns a hit on second lookup" do
      url = "https://mastodon.example/img/cat.jpg"
      body = "PNG-LIKE-BYTES"

      assert :miss = MediaProxyCache.lookup(url)
      assert :ok = MediaProxyCache.store(url, body, "image/jpeg")

      assert {:hit, %{path: path, content_type: "image/jpeg"}} =
               MediaProxyCache.lookup(url)

      assert File.read!(path) == body
    end

    test "two stores of the same URL last-write-wins (idempotent)" do
      url = "https://mastodon.example/img/duplicate.jpg"

      assert :ok = MediaProxyCache.store(url, "first", "image/jpeg")
      assert :ok = MediaProxyCache.store(url, "second", "image/jpeg")

      assert {:hit, %{path: path}} = MediaProxyCache.lookup(url)
      assert File.read!(path) == "second"
    end

    test "different URLs get different cache entries" do
      MediaProxyCache.store("https://a.example/x.jpg", "A", "image/jpeg")
      MediaProxyCache.store("https://b.example/x.jpg", "B", "image/jpeg")

      assert {:hit, %{path: path_a}} = MediaProxyCache.lookup("https://a.example/x.jpg")
      assert {:hit, %{path: path_b}} = MediaProxyCache.lookup("https://b.example/x.jpg")

      assert path_a != path_b
      assert File.read!(path_a) == "A"
      assert File.read!(path_b) == "B"
    end
  end

  describe "lookup/1 with disabled cache" do
    test "returns :miss without touching the DB" do
      Config.set("media_proxy_cache_enabled", false)
      assert :miss = MediaProxyCache.lookup("https://anywhere.example/x.jpg")
    end
  end

  describe "lookup/1 self-heals when file is gone" do
    test "deletes the orphan row and returns :miss" do
      url = "https://mastodon.example/img/orphan.jpg"
      MediaProxyCache.store(url, "bytes", "image/jpeg")

      {:hit, %{path: path}} = MediaProxyCache.lookup(url)
      File.rm!(path)

      assert :miss = MediaProxyCache.lookup(url)
      # And the row is gone — second miss doesn't have to re-prune.
      assert :miss = MediaProxyCache.lookup(url)
    end
  end

  describe "evict_by_domain/1" do
    test "drops only entries from the given domain" do
      MediaProxyCache.store("https://blocked.example/a.jpg", "A", "image/jpeg")
      MediaProxyCache.store("https://blocked.example/b.jpg", "B", "image/jpeg")
      MediaProxyCache.store("https://kept.example/c.jpg", "C", "image/jpeg")

      assert {:ok, 2} = MediaProxyCache.evict_by_domain("blocked.example")

      assert :miss = MediaProxyCache.lookup("https://blocked.example/a.jpg")
      assert :miss = MediaProxyCache.lookup("https://blocked.example/b.jpg")
      assert {:hit, _} = MediaProxyCache.lookup("https://kept.example/c.jpg")
    end
  end

  describe "evict_expired/1" do
    test "drops entries past the TTL" do
      Config.set("media_proxy_cache_ttl_days", 7)
      MediaProxyCache.store("https://stale.example/a.jpg", "A", "image/jpeg")

      # Backdate last_accessed_at to 8 days ago.
      eight_days_ago =
        DateTime.utc_now()
        |> DateTime.add(-8 * 24 * 3600, :second)

      from(e in MediaProxyCache,
        where: e.remote_origin_domain == "stale.example",
        update: [set: [last_accessed_at: ^eight_days_ago]]
      )
      |> Repo.update_all([])

      assert {:ok, 1} = MediaProxyCache.evict_expired()
      assert :miss = MediaProxyCache.lookup("https://stale.example/a.jpg")
    end

    test "keeps entries inside the TTL" do
      MediaProxyCache.store("https://fresh.example/a.jpg", "A", "image/jpeg")
      assert {:ok, 0} = MediaProxyCache.evict_expired()
      assert {:hit, _} = MediaProxyCache.lookup("https://fresh.example/a.jpg")
    end
  end

  describe "evict_lru/0" do
    test "drops oldest-accessed first when over the cap" do
      Config.set("media_proxy_cache_max_bytes", 100)

      # Three entries, each 50 bytes → 150 total, over the 100-byte cap.
      MediaProxyCache.store("https://a.example/1", String.duplicate("a", 50), "image/jpeg")
      :timer.sleep(20)
      MediaProxyCache.store("https://b.example/2", String.duplicate("b", 50), "image/jpeg")
      :timer.sleep(20)
      MediaProxyCache.store("https://c.example/3", String.duplicate("c", 50), "image/jpeg")

      assert {:ok, freed} = MediaProxyCache.evict_lru()
      assert freed >= 50

      # Oldest (a) is gone; newest (c) is kept.
      assert :miss = MediaProxyCache.lookup("https://a.example/1")
      assert {:hit, _} = MediaProxyCache.lookup("https://c.example/3")
    end

    test "no-op when under the cap" do
      Config.set("media_proxy_cache_max_bytes", 1_000_000)
      MediaProxyCache.store("https://a.example/1", "small", "image/jpeg")
      assert {:ok, 0} = MediaProxyCache.evict_lru()
    end
  end

  describe "touch/1" do
    test "bumps last_accessed_at" do
      url = "https://touch.example/a.jpg"
      MediaProxyCache.store(url, "bytes", "image/jpeg")

      {:hit, %{hash: hash}} = MediaProxyCache.lookup(url)
      hash_str = hash

      original = Repo.get(MediaProxyCache, hash_str).last_accessed_at
      :timer.sleep(20)
      :ok = MediaProxyCache.touch(hash_str)

      bumped = Repo.get(MediaProxyCache, hash_str).last_accessed_at
      assert DateTime.compare(bumped, original) == :gt
    end
  end

  describe "total_bytes/0" do
    test "sums byte_size across all entries" do
      MediaProxyCache.store("https://a.example/1", String.duplicate("a", 100), "image/jpeg")
      MediaProxyCache.store("https://b.example/2", String.duplicate("b", 50), "image/jpeg")
      assert MediaProxyCache.total_bytes() == 150
    end

    test "returns 0 for an empty cache" do
      assert MediaProxyCache.total_bytes() == 0
    end
  end
end
