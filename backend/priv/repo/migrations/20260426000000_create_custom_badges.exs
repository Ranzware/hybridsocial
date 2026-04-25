defmodule Hybridsocial.Repo.Migrations.CreateCustomBadges do
  use Ecto.Migration

  @moduledoc """
  Instance-wide custom badge catalog. Admins upload artwork +
  metadata; assignment to identities is a follow-up table. The
  built-in roles (owner/admin/moderator/verified_*) keep their
  hardcoded artwork in /badges/*.svg — this table is purely for
  custom badges introduced by the instance operator.
  """

  def change do
    create table(:custom_badges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :image_url, :string, null: false
      add :sort_order, :integer, default: 0, null: false
      add :enabled, :boolean, default: true, null: false
      add :created_by_id, references(:identities, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:custom_badges, [:slug])
    create index(:custom_badges, [:sort_order])
  end
end
