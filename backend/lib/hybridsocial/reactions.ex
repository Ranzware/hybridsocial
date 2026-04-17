defmodule Hybridsocial.Reactions do
  @moduledoc """
  Public API for the premium reaction emoji catalog.

  Default reactions (the fixed 7 in `@default_reactions`) are
  available to every user and require no DB lookup. Premium
  reactions are admin-curated and capped at 7 entries — combined
  ceiling is 14 reactions per message that a premium user can pick
  from.
  """
  import Ecto.Query

  alias Hybridsocial.Reactions.PremiumReactionEmoji
  alias Hybridsocial.Repo

  @default_reactions ~w(like love care angry sad lol wow)
  @max_premium 7

  @doc "List of always-available reaction shortcodes."
  def default_reactions, do: @default_reactions

  @doc "Maximum number of premium reaction slots an admin can configure."
  def max_premium_slots, do: @max_premium

  @doc "Returns enabled premium reactions ordered by position."
  def list_enabled_premium do
    PremiumReactionEmoji
    |> where([e], e.enabled == true)
    |> order_by([e], asc: e.position, asc: e.inserted_at)
    |> Repo.all()
  end

  @doc "Returns ALL premium reactions (admin view, includes disabled)."
  def list_all_premium do
    PremiumReactionEmoji
    |> order_by([e], asc: e.position, asc: e.inserted_at)
    |> Repo.all()
  end

  @doc "Returns true if `shortcode` is in the default-reactions set."
  def default_reaction?(shortcode) when is_binary(shortcode),
    do: shortcode in @default_reactions

  def default_reaction?(_), do: false

  @doc "Returns true if `shortcode` is an enabled premium reaction."
  def premium_reaction?(shortcode) when is_binary(shortcode) do
    Repo.exists?(
      from(e in PremiumReactionEmoji,
        where: e.shortcode == ^shortcode and e.enabled == true
      )
    )
  end

  def premium_reaction?(_), do: false

  @doc """
  Create a new premium reaction. Refuses when the cap is reached.
  Caller is expected to be an admin.
  """
  def create_premium(attrs, admin_id) do
    if count_total() >= @max_premium do
      {:error, :cap_reached}
    else
      attrs = Map.put(stringify(attrs), "created_by", admin_id)

      %PremiumReactionEmoji{}
      |> PremiumReactionEmoji.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc "Update an existing premium reaction by ID."
  def update_premium(id, attrs) do
    case Repo.get(PremiumReactionEmoji, id) do
      nil ->
        {:error, :not_found}

      emoji ->
        emoji
        |> PremiumReactionEmoji.changeset(stringify(attrs))
        |> Repo.update()
    end
  end

  @doc "Delete a premium reaction by ID."
  def delete_premium(id) do
    case Repo.get(PremiumReactionEmoji, id) do
      nil -> {:error, :not_found}
      emoji -> Repo.delete(emoji)
    end
  end

  defp count_total do
    Repo.aggregate(PremiumReactionEmoji, :count, :id)
  end

  defp stringify(attrs) when is_map(attrs) do
    for {k, v} <- attrs, into: %{}, do: {to_string(k), v}
  end
end
