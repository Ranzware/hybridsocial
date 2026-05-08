defmodule Hybridsocial.Repo.Migrations.AddGroupPageToPostDrafts do
  use Ecto.Migration

  # Drafts started inside a group or on a page used to lose that
  # context the moment the user clicked "Save draft" — the columns
  # didn't exist, so resuming the draft published it as a regular
  # profile post. These mirror the matching columns on `posts` so
  # the composer can carry the anchor through draft round-trips and
  # so the drafts list can show "Posting to <group>" / "Posting to
  # <page>" chips.
  def change do
    alter table(:post_drafts) do
      add :group_id, :binary_id
      add :page_id, :binary_id
    end
  end
end
