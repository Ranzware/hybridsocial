defmodule Hybridsocial.Social.PostMention do
  @moduledoc """
  Records that a post is addressed to an identity. Populated for both
  regular mentions (`@handle` in content) and the explicit recipient
  list of direct-visibility posts. Drives:

    * who can see a `visibility: direct` post — the author plus any
      identity listed here;
    * mention notifications (fan-out from `Social.Posts` calls into
      `Notifications`);
    * the profile "Direct" tab, which surfaces posts the viewer is
      the author OR audience of.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "post_mentions" do
    belongs_to :post, Hybridsocial.Social.Post
    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec, inserted_at: :created_at, updated_at: false)
  end

  def changeset(mention, attrs) do
    mention
    |> cast(attrs, [:post_id, :identity_id])
    |> validate_required([:post_id, :identity_id])
    |> unique_constraint([:post_id, :identity_id])
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:identity_id)
  end
end
