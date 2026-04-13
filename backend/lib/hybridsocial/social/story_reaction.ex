defmodule Hybridsocial.Social.StoryReaction do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "story_reactions" do
    field :emoji, :string

    belongs_to :story, Hybridsocial.Social.Story
    belongs_to :identity, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:story_id, :identity_id, :emoji])
    |> validate_required([:story_id, :identity_id, :emoji])
    |> validate_length(:emoji, min: 1, max: 32)
    |> unique_constraint([:story_id, :identity_id])
    |> foreign_key_constraint(:story_id)
    |> foreign_key_constraint(:identity_id)
  end
end
