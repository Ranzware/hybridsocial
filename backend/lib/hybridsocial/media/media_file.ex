defmodule Hybridsocial.Media.MediaFile do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @storage_backends ~w(local S3)
  @processing_statuses ~w(pending processing ready failed)

  schema "media" do
    field :content_type, :string
    field :file_size, :integer
    field :storage_backend, :string, default: "local"
    field :storage_path, :string
    field :blurhash, :string
    field :alt_text, :string
    field :width, :integer
    field :height, :integer
    field :duration, :float
    field :thumbnail_path, :string
    field :processing_status, :string, default: "pending"
    field :metadata, :map, default: %{}
    field :deleted_at, :utc_datetime_usec
    field :folder_id, :binary_id
    field :content_hash, :string
    # Federated attachments: remote_url is the original URL on the
    # author's instance; we never store the bytes locally for these.
    # Local uploads leave both nil.
    field :remote_url, :string
    field :remote_origin_domain, :string

    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :post, Hybridsocial.Social.Post
    has_many :variants, Hybridsocial.Media.MediaVariant, foreign_key: :media_id

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(media, attrs) do
    media
    |> cast(attrs, [
      :identity_id,
      :content_type,
      :file_size,
      :storage_backend,
      :storage_path,
      :blurhash,
      :alt_text,
      :width,
      :height,
      :duration,
      :thumbnail_path,
      :processing_status,
      :metadata
    ])
    |> validate_required([:identity_id, :content_type, :file_size, :storage_path])
    |> validate_inclusion(:storage_backend, @storage_backends)
    |> validate_inclusion(:processing_status, @processing_statuses)
    |> foreign_key_constraint(:identity_id)
  end

  @doc "Attach a media file to a post. Ownership check happens at the context level."
  def attach_to_post_changeset(media, post_id) do
    change(media, post_id: post_id)
  end

  @doc """
  Changeset for a federated attachment. The bytes live on the
  author's remote instance; we just record the URL + content type
  so the proxy can dereference on first request. `storage_path`
  stays nil — that's the signal that this row is "remote, not yet
  cached locally".
  """
  def remote_changeset(media, attrs) do
    media
    |> cast(attrs, [
      :identity_id,
      :post_id,
      :content_type,
      :remote_url,
      :remote_origin_domain,
      :alt_text,
      :width,
      :height,
      :duration,
      :blurhash,
      :metadata
    ])
    |> validate_required([:identity_id, :remote_url, :remote_origin_domain])
    |> change(processing_status: "ready", file_size: 0)
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:post_id)
  end

  def update_alt_text_changeset(media, attrs) do
    media
    |> cast(attrs, [:alt_text])
  end

  def soft_delete_changeset(media) do
    media
    |> change(deleted_at: DateTime.utc_now())
  end
end
