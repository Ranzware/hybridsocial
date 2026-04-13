defmodule Hybridsocial.Social.StoryView do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "story_views" do
    field :viewed_at, :utc_datetime_usec

    belongs_to :story, Hybridsocial.Social.Story
    belongs_to :viewer, Hybridsocial.Accounts.Identity

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(view, attrs) do
    view
    |> cast(attrs, [:story_id, :viewer_id])
    |> validate_required([:story_id, :viewer_id])
    |> put_change(:viewed_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
    |> unique_constraint([:story_id, :viewer_id])
    |> foreign_key_constraint(:story_id)
    |> foreign_key_constraint(:viewer_id)
  end
end
