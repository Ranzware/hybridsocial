defmodule HybridsocialWeb.Api.V1.BadgeController do
  @moduledoc "Public read access to the instance custom-badge catalog."
  use HybridsocialWeb, :controller

  alias Hybridsocial.Content.Badges

  def index(conn, _params) do
    badges = Badges.list_badges()
    json(conn, Enum.map(badges, &serialize/1))
  end

  defp serialize(badge) do
    %{
      id: badge.id,
      slug: badge.slug,
      name: badge.name,
      description: badge.description,
      image_url: badge.image_url,
      sort_order: badge.sort_order
    }
  end
end
