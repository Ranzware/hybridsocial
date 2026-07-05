defmodule Hybridsocial.Cache.TokenCache do
  @moduledoc "Identity/token caching to avoid DB lookups on every request."

  alias Hybridsocial.Cache

  @token_status_ttl_active 30
  @token_status_ttl_revoked 3600

  def cache_identity(identity_id, identity_data, ttl \\ 300) do
    Cache.set("identity:#{identity_id}", identity_data, ttl)
  end

  def get_cached_identity(identity_id) do
    Cache.get("identity:#{identity_id}")
  end

  def invalidate_identity(identity_id) do
    Cache.delete("identity:#{identity_id}")
  end

  # --- Token revocation status cache ---
  #
  # The Auth plug checks this on every request so that a logged-out or
  # revoked access token is rejected immediately rather than waiting
  # for the JWT to expire. Active tokens are cached for a short window
  # (30 s) so a revocation takes effect within that window; revoked
  # tokens are cached for 1 h.

  def token_status(token_hash) do
    case Cache.get("token_status:#{token_hash}") do
      "active" -> :active
      "revoked" -> :revoked
      _ -> :unknown
    end
  end

  def cache_token_active(token_hash) do
    Cache.set("token_status:#{token_hash}", "active", @token_status_ttl_active)
  end

  def cache_token_revoked(token_hash) do
    Cache.set("token_status:#{token_hash}", "revoked", @token_status_ttl_revoked)
  end

  def invalidate_token_status(token_hash) do
    Cache.delete("token_status:#{token_hash}")
  end
end
