defmodule Hybridsocial.Content.Badges do
  @moduledoc """
  Context module for the instance-wide custom badge catalog. The
  built-in role badges (owner/admin/moderator/verified_*) live in
  the frontend's static /badges/*.svg — this module manages the
  *custom* badges an admin uploads on top of those.
  """

  import Ecto.Query
  alias Hybridsocial.Repo
  alias Hybridsocial.Content.CustomBadge

  @doc "List all enabled badges in display order. Pass enabled: false to include hidden ones (admin view)."
  def list_badges(opts \\ []) do
    only_enabled = Keyword.get(opts, :only_enabled, true)

    query =
      CustomBadge
      |> order_by([b], asc: b.sort_order, asc: b.inserted_at)

    query =
      if only_enabled, do: where(query, [b], b.enabled == true), else: query

    Repo.all(query)
  end

  def get_badge(id), do: Repo.get(CustomBadge, id)
  def get_badge_by_slug(slug), do: Repo.get_by(CustomBadge, slug: slug)

  def create_badge(attrs) do
    %CustomBadge{}
    |> CustomBadge.changeset(attrs)
    |> Repo.insert()
  end

  def update_badge(id, attrs) do
    case get_badge(id) do
      nil -> {:error, :not_found}
      badge -> badge |> CustomBadge.changeset(attrs) |> Repo.update()
    end
  end

  def delete_badge(id) do
    case get_badge(id) do
      nil -> {:error, :not_found}
      badge -> Repo.delete(badge)
    end
  end
end
