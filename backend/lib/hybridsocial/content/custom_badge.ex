defmodule Hybridsocial.Content.CustomBadge do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "custom_badges" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :image_url, :string
    field :sort_order, :integer, default: 0
    field :enabled, :boolean, default: true

    belongs_to :created_by, Hybridsocial.Accounts.Identity, foreign_key: :created_by_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(badge, attrs) do
    badge
    |> cast(attrs, [:slug, :name, :description, :image_url, :sort_order, :enabled, :created_by_id])
    |> validate_required([:slug, :name, :image_url])
    |> update_change(:slug, fn s -> s |> String.downcase() |> String.trim() end)
    |> validate_format(:slug, ~r/\A[a-z0-9_-]{2,40}\z/,
      message: "must be 2–40 characters of letters, numbers, dashes, or underscores"
    )
    |> validate_length(:name, min: 1, max: 60)
    |> validate_length(:description, max: 280)
    |> validate_length(:image_url, max: 2048)
    |> unique_constraint(:slug)
  end
end
