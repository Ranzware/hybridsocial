defmodule Hybridsocial.Reactions.PremiumReactionEmoji do
  @moduledoc """
  Catalog row for a premium-tier reaction emoji.

  Either `character` (a unicode emoji like "🔥") or `image_url`
  (a hosted SVG/PNG sticker) must be present — the picker renders
  whichever is set. `shortcode` is the canonical identifier sent
  in the API and stored in MessageReaction.emoji.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "premium_reaction_emojis" do
    field :shortcode, :string
    field :character, :string
    field :image_url, :string
    field :position, :integer, default: 0
    field :enabled, :boolean, default: true
    field :created_by, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  @valid_shortcode ~r/^[a-z0-9_]{2,32}$/

  def changeset(emoji, attrs) do
    emoji
    |> cast(attrs, [:shortcode, :character, :image_url, :position, :enabled, :created_by])
    |> validate_required([:shortcode])
    |> validate_format(:shortcode, @valid_shortcode,
      message: "must be 2-32 chars, lowercase letters/digits/underscores"
    )
    |> validate_either_character_or_image()
    |> unique_constraint(:shortcode, name: :premium_reaction_emojis_shortcode_idx)
  end

  defp validate_either_character_or_image(changeset) do
    char = get_field(changeset, :character)
    img = get_field(changeset, :image_url)

    cond do
      is_binary(char) and char != "" -> changeset
      is_binary(img) and img != "" -> changeset
      true -> add_error(changeset, :character, "either character or image_url is required")
    end
  end
end
