defmodule HybridsocialWeb.Api.V1.Admin.CustomBadgesController do
  @moduledoc """
  Admin CRUD for the instance-wide custom badge catalog. Admins
  upload artwork (any image URL the media pipeline returns is fine)
  + name + slug; the catalog is exposed publicly via
  GET /api/v1/badges so the frontend can render badges that aren't
  one of the built-in role/verification ones.
  """
  use HybridsocialWeb, :controller

  alias Hybridsocial.Content.Badges

  @badge_fields ~w(slug name description image_url sort_order enabled)

  def index(conn, _params) do
    # Admin view: include hidden badges so the operator can re-enable
    # them. The public endpoint filters them out.
    badges = Badges.list_badges(only_enabled: false)
    json(conn, Enum.map(badges, &serialize/1))
  end

  def create(conn, params) do
    identity = conn.assigns.current_identity

    attrs =
      params
      |> Map.take(@badge_fields)
      |> Map.put("created_by_id", identity.id)

    case Badges.create_badge(attrs) do
      {:ok, badge} ->
        conn |> put_status(:created) |> json(serialize(badge))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Badges.update_badge(id, Map.take(params, @badge_fields)) do
      {:ok, badge} ->
        json(conn, serialize(badge))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "badge.not_found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Badges.delete_badge(id) do
      {:ok, _} -> send_resp(conn, :no_content, "")
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "badge.not_found"})
    end
  end

  defp serialize(badge) do
    %{
      id: badge.id,
      slug: badge.slug,
      name: badge.name,
      description: badge.description,
      image_url: badge.image_url,
      sort_order: badge.sort_order,
      enabled: badge.enabled,
      created_at: badge.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
