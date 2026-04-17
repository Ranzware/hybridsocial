defmodule Hybridsocial.Repo.Migrations.CreatePremiumReactionEmojis do
  use Ecto.Migration

  # Admin-curated catalog of emoji that premium users can react with
  # on messages and posts. Capped at 7 entries app-side so premium
  # users get the standard 7 + up to 7 admin-picked = 14 max.
  #
  # Curation matters: the platform owner doesn't want hostile emojis
  # (middle finger, slurs, etc.) appearing as reaction options.
  def change do
    create table(:premium_reaction_emojis, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :shortcode, :string, null: false
      add :character, :string
      add :image_url, :text
      add :position, :integer, null: false, default: 0
      add :enabled, :boolean, null: false, default: true
      add :created_by, :binary_id

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:premium_reaction_emojis, [:shortcode],
             name: :premium_reaction_emojis_shortcode_idx
           )

    create index(:premium_reaction_emojis, [:enabled, :position],
             name: :premium_reaction_emojis_enabled_position_idx
           )
  end
end
