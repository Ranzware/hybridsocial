defmodule Hybridsocial.Media.MediaProxyTest do
  use Hybridsocial.DataCase, async: false

  alias Hybridsocial.Config
  alias Hybridsocial.Media.MediaProxy

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Hybridsocial.Repo, {:shared, self()})
    start_supervised!(Hybridsocial.Config.Store)
    :ok
  end

  describe "url/1 with proxy enabled" do
    setup do
      Config.set("media_proxy_enabled", true)
      :ok
    end

    test "rewrites a remote URL to a signed /proxy/media/ path" do
      remote = "https://mastodon.example/system/media_attachments/files/1/original/img.jpg"
      proxied = MediaProxy.url(remote)

      assert String.contains?(proxied, "/proxy/media/")
      refute proxied == remote
      # The original URL is the last segment, base64url-encoded.
      assert String.contains?(proxied, Base.url_encode64(remote, padding: false))
    end

    test "passes same-origin URLs through unchanged" do
      local = HybridsocialWeb.Endpoint.url() <> "/uploads/local.jpg"
      assert MediaProxy.url(local) == local
    end

    test "round-trips: verify_url decodes what url/1 produced" do
      remote = "https://mastodon.example/img/2.png"
      proxied = MediaProxy.url(remote)

      # Last two path segments are the signature and encoded URL.
      parts = String.split(proxied, "/")
      [encoded, signature | _] = Enum.reverse(parts)
      assert {:ok, ^remote} = MediaProxy.verify_url(signature, encoded)
    end

    test "returns nil unchanged" do
      assert MediaProxy.url(nil) == nil
    end
  end

  describe "url/1 with proxy disabled" do
    setup do
      Config.set("media_proxy_enabled", false)
      :ok
    end

    test "returns the remote URL untouched" do
      remote = "https://mastodon.example/img.jpg"
      assert MediaProxy.url(remote) == remote
    end
  end

  describe "verify_url/2" do
    test "rejects a tampered signature" do
      remote = "https://mastodon.example/img.jpg"
      encoded = Base.url_encode64(remote, padding: false)
      assert {:error, :invalid_signature} = MediaProxy.verify_url("tampered", encoded)
    end

    test "rejects a malformed encoded URL even with a valid-looking signature" do
      # Build a signature for some other content, then submit garbage.
      assert {:error, :invalid_signature} =
               MediaProxy.verify_url("AAAA", "not-valid-base64!!!")
    end
  end
end
