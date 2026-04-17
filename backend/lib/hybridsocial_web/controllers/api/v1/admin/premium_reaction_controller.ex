defmodule HybridsocialWeb.Api.V1.Admin.PremiumReactionController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Reactions

  # GET /api/v1/admin/premium_reactions — full catalog including disabled.
  def index(conn, _params) do
    emojis = Reactions.list_all_premium()
    json(conn, Enum.map(emojis, &serialize/1))
  end

  # POST /api/v1/admin/premium_reactions
  def create(conn, params) do
    admin = conn.assigns.current_identity

    case Reactions.create_premium(params, admin.id) do
      {:ok, emoji} ->
        conn |> put_status(:created) |> json(serialize(emoji))

      {:error, :cap_reached} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "premium_reaction.cap_reached",
          max: Reactions.max_premium_slots()
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # PATCH /api/v1/admin/premium_reactions/:id
  def update(conn, %{"id" => id} = params) do
    case Reactions.update_premium(id, Map.delete(params, "id")) do
      {:ok, emoji} ->
        json(conn, serialize(emoji))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "premium_reaction.not_found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/admin/premium_reactions/:id
  def delete(conn, %{"id" => id}) do
    case Reactions.delete_premium(id) do
      {:ok, _emoji} ->
        json(conn, %{message: "premium_reaction.deleted"})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "premium_reaction.not_found"})
    end
  end

  defp serialize(emoji) do
    %{
      id: emoji.id,
      shortcode: emoji.shortcode,
      character: emoji.character,
      image_url: emoji.image_url,
      position: emoji.position,
      enabled: emoji.enabled,
      created_at: emoji.inserted_at
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
