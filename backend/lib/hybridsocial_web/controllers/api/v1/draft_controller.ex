defmodule HybridsocialWeb.Api.V1.DraftController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Social.Drafts

  # GET /api/v1/drafts
  def index(conn, _params) do
    identity = conn.assigns.current_identity
    drafts = Drafts.list_drafts(identity.id)

    conn |> put_status(:ok) |> json(%{drafts: Enum.map(drafts, &serialize/1)})
  end

  # GET /api/v1/drafts/:id
  def show(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Drafts.get_draft(id, identity.id) do
      {:ok, draft} -> json(conn, serialize(draft))
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "draft.not_found"})
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "draft.forbidden"})
    end
  end

  # POST /api/v1/drafts
  def create(conn, params) do
    identity = conn.assigns.current_identity

    case Drafts.create_draft(identity.id, params) do
      {:ok, draft} ->
        conn |> put_status(:created) |> json(serialize(draft))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # PUT /api/v1/drafts/:id
  def update(conn, %{"id" => id} = params) do
    identity = conn.assigns.current_identity

    case Drafts.update_draft(id, identity.id, Map.delete(params, "id")) do
      {:ok, draft} ->
        json(conn, serialize(draft))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "draft.not_found"})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "draft.forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation.failed", details: format_errors(changeset)})
    end
  end

  # DELETE /api/v1/drafts/:id
  def delete(conn, %{"id" => id}) do
    identity = conn.assigns.current_identity

    case Drafts.delete_draft(id, identity.id) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{error: "draft.not_found"})
      {:error, :forbidden} -> conn |> put_status(:forbidden) |> json(%{error: "draft.forbidden"})
    end
  end

  defp serialize(draft) do
    %{
      id: draft.id,
      content: draft.content,
      spoiler_text: draft.spoiler_text,
      sensitive: draft.sensitive,
      visibility: draft.visibility,
      media_ids: draft.media_ids || [],
      parent_id: draft.parent_id,
      quote_id: draft.quote_id,
      scheduled_at: draft.scheduled_at,
      poll_options: draft.poll_options,
      poll_multiple: draft.poll_multiple,
      poll_expires_at: draft.poll_expires_at,
      created_at: draft.inserted_at,
      updated_at: draft.updated_at
    }
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
