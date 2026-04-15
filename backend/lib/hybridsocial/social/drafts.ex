defmodule Hybridsocial.Social.Drafts do
  @moduledoc """
  Post drafts — in-flight post composition saved by users to finish later.

  A draft is a snapshot of composer state (content, visibility, attached
  media_ids, poll, reply/quote target, scheduled_at). Drafts are private to
  the authoring identity and never federate.

  Media referenced by a draft stays attached to its author (post_id = nil)
  until the user actually publishes; publishing flows through the normal
  `Posts.create_post/3` path which handles the media attach.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Social.PostDraft

  @default_limit 50
  @max_limit 100

  @doc "Returns the caller's drafts, newest-updated first."
  def list_drafts(identity_id, opts \\ []) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)

    PostDraft
    |> where([d], d.identity_id == ^identity_id)
    |> order_by([d], desc: d.updated_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Fetches a single draft, only if owned by `identity_id`."
  def get_draft(draft_id, identity_id) do
    case Repo.get(PostDraft, draft_id) do
      nil -> {:error, :not_found}
      %PostDraft{identity_id: ^identity_id} = draft -> {:ok, draft}
      _ -> {:error, :forbidden}
    end
  end

  @doc "Creates a draft owned by `identity_id`."
  def create_draft(identity_id, attrs) do
    %PostDraft{}
    |> PostDraft.create_changeset(Map.put(to_string_map(attrs), "identity_id", identity_id))
    |> Repo.insert()
  end

  @doc "Updates a draft. Returns `{:error, :not_found | :forbidden}` if the caller doesn't own it."
  def update_draft(draft_id, identity_id, attrs) do
    with {:ok, draft} <- get_draft(draft_id, identity_id) do
      draft
      |> PostDraft.update_changeset(to_string_map(attrs))
      |> Repo.update()
    end
  end

  @doc "Deletes a draft. Returns `{:error, :not_found | :forbidden}` if the caller doesn't own it."
  def delete_draft(draft_id, identity_id) do
    with {:ok, draft} <- get_draft(draft_id, identity_id) do
      Repo.delete(draft)
    end
  end

  defp to_string_map(%{} = attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
