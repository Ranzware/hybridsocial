defmodule Hybridsocial.Repo.Migrations.WidenIdentityUrlColumns do
  use Ecto.Migration

  # ActivityPub URLs — especially remote avatar/header CDN links, but also
  # actor/inbox/collection URLs from other servers — routinely exceed 255
  # characters. The columns were varchar(255), which truncated (and raised)
  # on such actors. This bit the Pleroma follow-graph import (thousands of
  # remote endpoints) and is a latent bug for `create_remote_identity` on
  # normal federation too. Widen to text. varchar(255) -> text is a
  # metadata-only change in Postgres (no table rewrite).

  @url_cols ~w(ap_actor_url avatar_url header_url inbox_url outbox_url
               followers_url following_url featured_url shared_inbox_url)a

  def up do
    alter table(:identities) do
      for col <- @url_cols, do: modify(col, :text)
    end
  end

  def down do
    alter table(:identities) do
      for col <- @url_cols, do: modify(col, :string)
    end
  end
end
