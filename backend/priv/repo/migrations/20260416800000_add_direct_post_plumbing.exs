defmodule Hybridsocial.Repo.Migrations.AddDirectPostPlumbing do
  use Ecto.Migration

  def change do
    # Tracks which identities a post is addressed to. Populated for
    # posts with visibility "direct" (so the "Direct" tab can show
    # posts the viewer is a recipient of, not just posts they
    # authored) and also on posts with regular mentions (so we can
    # surface mention notifications + enforce per-recipient visibility
    # on followers-only / direct posts).
    create table(:post_mentions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
    end

    create unique_index(:post_mentions, [:post_id, :identity_id])
    create index(:post_mentions, [:identity_id])

    # Per-domain cache of remote software identification (via
    # NodeInfo). Drives outbound DM routing: Pleroma/Akkoma get
    # ChatMessage activities; everyone else gets direct-visibility
    # posts. Entries are refreshed lazily when stale.
    create table(:remote_instances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :domain, :string, null: false
      add :software, :string
      add :version, :string
      # NodeInfo 2.1 `metadata.features` array — the signal we actually
      # use to decide whether the peer accepts Create{ChatMessage}.
      # Pleroma + Akkoma publish `pleroma_chat_messages` here; Mastodon
      # publishes nothing resembling chat. Storing the raw list rather
      # than a single "chat_capable" bool lets admins audit why a
      # decision went the way it did, and future software can advertise
      # their own chat feature string without a code change.
      add :features, {:array, :string}, default: []
      # Admin escape hatch: if the autodetect gets it wrong for a
      # particular instance, force it one way or the other. `nil` means
      # defer to features/software.
      add :chat_capable_override, :boolean
      add :fetched_at, :utc_datetime_usec
      add :last_error, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:remote_instances, [:domain])
  end
end
