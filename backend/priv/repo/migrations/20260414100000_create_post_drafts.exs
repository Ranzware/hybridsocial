defmodule Hybridsocial.Repo.Migrations.CreatePostDrafts do
  use Ecto.Migration

  def change do
    create table(:post_drafts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :identity_id, references(:identities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :content, :text
      add :spoiler_text, :string
      add :sensitive, :boolean, default: false, null: false
      add :visibility, :string, default: "public", null: false
      add :media_ids, {:array, :binary_id}, default: []

      add :parent_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
      add :quote_id, references(:posts, type: :binary_id, on_delete: :nilify_all)

      add :scheduled_at, :utc_datetime_usec

      add :poll_options, {:array, :string}
      add :poll_multiple, :boolean, default: false, null: false
      add :poll_expires_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:post_drafts, [:identity_id, :updated_at])
  end
end
