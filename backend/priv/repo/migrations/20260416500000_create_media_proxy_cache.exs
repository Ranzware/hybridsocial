defmodule Hybridsocial.Repo.Migrations.CreateMediaProxyCache do
  use Ecto.Migration

  # Phase 2 of the federated-media proxy: an on-disk cache so we
  # don't refetch the same remote bytes on every page load.
  #
  # Keyed by SHA-256 of the remote URL so two posts referencing the
  # same image share one cache entry. `last_accessed_at` is updated
  # on every cache hit and drives LRU eviction; `remote_origin_domain`
  # is denormalized so we can flush an entire instance's content
  # cheaply when it's suspended/blocked.
  def change do
    create table(:media_proxy_cache, primary_key: false) do
      add :url_hash, :string, primary_key: true, size: 64
      add :remote_url, :text, null: false
      add :remote_origin_domain, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :bigint, null: false
      add :storage_path, :text, null: false

      add :fetched_at, :utc_datetime_usec, null: false
      add :last_accessed_at, :utc_datetime_usec, null: false
    end

    create index(:media_proxy_cache, [:last_accessed_at], name: :media_proxy_cache_lru_idx)

    create index(:media_proxy_cache, [:remote_origin_domain], name: :media_proxy_cache_domain_idx)
  end
end
