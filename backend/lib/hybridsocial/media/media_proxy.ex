defmodule Hybridsocial.Media.MediaProxy do
  @moduledoc """
  Proxies remote media URLs through the local server.

  Generates HMAC-signed URLs that point to the local media proxy endpoint,
  and verifies those signatures on incoming requests.
  """

  alias Hybridsocial.Config

  @doc "Check if media proxying is enabled."
  def enabled? do
    Config.get("media_proxy_enabled", false)
  end

  @doc """
  Convert a remote URL to a proxied URL with HMAC signature.
  Returns the original URL if media proxy is disabled or the URL is local.
  """
  def url(nil), do: nil

  def url(remote_url) when is_binary(remote_url) do
    if enabled?() and not local_url?(remote_url) do
      # Prefer the isolated media origin (e.g. https://media.arab.place)
      # — matches where local uploads are served from and keeps
      # every piece of user-origin content off the main app cookie.
      base = media_host() || HybridsocialWeb.Endpoint.url()
      encoded = Base.url_encode64(remote_url, padding: false)
      signature = sign(encoded)
      "#{base}/proxy/media/#{signature}/#{encoded}"
    else
      remote_url
    end
  end

  defp media_host do
    case Application.get_env(:hybridsocial, :media_host) do
      host when is_binary(host) and host != "" -> String.trim_trailing(host, "/")
      _ -> nil
    end
  end

  @doc """
  Verify HMAC signature on a proxied URL.
  Returns {:ok, remote_url} or {:error, :invalid_signature}.
  """
  def verify_url(signature, encoded_url) do
    expected_sig = sign(encoded_url)

    if Plug.Crypto.secure_compare(expected_sig, signature) do
      case Base.url_decode64(encoded_url, padding: false) do
        {:ok, remote_url} -> {:ok, remote_url}
        :error -> {:error, :invalid_url}
      end
    else
      {:error, :invalid_signature}
    end
  end

  defp sign(data) do
    secret = secret_key()

    :crypto.mac(:hmac, :sha256, secret, data)
    |> Base.url_encode64(padding: false)
  end

  defp secret_key do
    Application.get_env(:hybridsocial, :secret_key_base) ||
      raise "media proxy: secret_key_base is not configured — refusing to sign with a default key"
  end

  # Our own content — never proxy it. Covers both the app host and the
  # configured media host (e.g. media.example.com backed by S3/R2), so
  # media served from our own bucket is handed to the client directly
  # instead of being round-tripped through the proxy. This also keeps
  # actors/posts imported from a same-infra instance (whose media URLs
  # point at our media host) served straight from the bucket.
  defp local_url?(url) do
    remote_host = URI.parse(url).host
    local_host = URI.parse(HybridsocialWeb.Endpoint.url()).host

    media_hostname =
      case media_host() do
        h when is_binary(h) -> URI.parse(h).host
        _ -> nil
      end

    remote_host == local_host or (not is_nil(media_hostname) and remote_host == media_hostname)
  end
end
