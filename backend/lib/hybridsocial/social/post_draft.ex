defmodule Hybridsocial.Social.PostDraft do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_visibilities ~w(public followers group direct list)

  schema "post_drafts" do
    field :content, :string
    field :spoiler_text, :string
    field :sensitive, :boolean, default: false
    field :visibility, :string, default: "public"
    field :media_ids, {:array, :binary_id}, default: []
    field :scheduled_at, :utc_datetime_usec

    # Anchor for the eventual post: a draft started inside a group or on
    # a page carries that context so resuming it from the drafts list
    # publishes back to the same place. Plain `:binary_id` (not a
    # belongs_to) to match how `posts.group_id` / `posts.page_id` are
    # modeled — pages are Identity rows, not their own schema, and we
    # don't need an FK constraint here since the draft is private and
    # publishing re-validates.
    field :group_id, :binary_id
    field :page_id, :binary_id

    field :poll_options, {:array, :string}
    field :poll_multiple, :boolean, default: false
    field :poll_expires_at, :utc_datetime_usec

    belongs_to :identity, Hybridsocial.Accounts.Identity
    belongs_to :parent, Hybridsocial.Social.Post
    belongs_to :quote, Hybridsocial.Social.Post

    timestamps(type: :utc_datetime_usec)
  end

  @cast_fields [
    :identity_id,
    :content,
    :spoiler_text,
    :sensitive,
    :visibility,
    :media_ids,
    :parent_id,
    :quote_id,
    :group_id,
    :page_id,
    :scheduled_at,
    :poll_options,
    :poll_multiple,
    :poll_expires_at
  ]

  def create_changeset(draft, attrs) do
    draft
    |> cast(attrs, @cast_fields)
    |> validate_required([:identity_id])
    |> validate_inclusion(:visibility, @valid_visibilities)
    |> validate_length(:content, max: 10_000)
    |> validate_length(:spoiler_text, max: 500)
    |> foreign_key_constraint(:identity_id)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:quote_id)
  end

  def update_changeset(draft, attrs) do
    draft
    |> cast(attrs, @cast_fields -- [:identity_id])
    |> validate_inclusion(:visibility, @valid_visibilities)
    |> validate_length(:content, max: 10_000)
    |> validate_length(:spoiler_text, max: 500)
  end
end
