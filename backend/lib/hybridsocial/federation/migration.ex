defmodule Hybridsocial.Federation.Migration do
  @moduledoc """
  Handles actor migration between instances using the ActivityPub Move activity.

  Supports both outgoing migrations (local user moves to another server) and
  incoming migrations (remote user moves, followers should be redirected).
  """

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social
  alias Hybridsocial.Social.Follow
  alias Hybridsocial.Federation.Publisher

  require Logger

  # --- Outgoing Migration ---

  @doc """
  Initiates an outgoing migration for a local identity to a target AP ID.

  Steps:
  1. Verify the target actor exists (fetch via HTTP)
  2. Verify target's alsoKnownAs includes our actor URL
  3. Set moved_to on the identity
  4. Build Move activity and publish to followers
  """
  def initiate_migration(identity_id, target_ap_id) do
    with {:ok, identity} <- fetch_identity(identity_id),
         :ok <- verify_target_exists(target_ap_id),
         :ok <- verify_target_also_known_as(target_ap_id, identity),
         {:ok, updated_identity} <- set_moved_to(identity, target_ap_id),
         {:ok, _count} <- publish_move(updated_identity, target_ap_id) do
      {:ok, updated_identity}
    end
  end

  # --- Incoming Migration ---

  @doc """
  Processes an incoming Move activity.

  Steps:
  1. Extract actor (old account) and target (new account)
  2. Verify target's alsoKnownAs includes the actor
  3. For each local follower of the old account: create follow to new account
  4. Cache the redirect info
  """
  def process_move(%{"actor" => actor_ap_id, "target" => target_ap_id} = _activity)
      when is_binary(actor_ap_id) and is_binary(target_ap_id) do
    with {:ok, old_identity} <- resolve_identity(actor_ap_id),
         :ok <- verify_target_also_known_as(target_ap_id, old_identity),
         {:ok, new_identity} <- resolve_or_create_identity(target_ap_id) do
      # Migrate local followers
      migrate_followers(old_identity.id, new_identity.id)

      # Mark old identity as moved
      set_moved_to(old_identity, target_ap_id)

      {:ok, %{old: old_identity, new: new_identity}}
    end
  end

  def process_move(%{"actor" => actor_ap_id, "object" => target_ap_id} = activity)
      when is_binary(actor_ap_id) and is_binary(target_ap_id) do
    # Handle Move where target is in "object" field instead of "target"
    process_move(Map.put(activity, "target", target_ap_id))
  end

  def process_move(_), do: {:error, :invalid_move_activity}

  # --- AlsoKnownAs Management ---

  @doc """
  Adds an alsoKnownAs URI to an identity.
  This is a prerequisite for incoming migration.
  """
  def add_also_known_as(identity_id, uri) do
    with {:ok, identity} <- fetch_identity(identity_id) do
      current = identity.also_known_as || []

      if uri in current do
        {:ok, identity}
      else
        identity
        |> Ecto.Changeset.change(also_known_as: current ++ [uri])
        |> Repo.update()
      end
    end
  end

  @doc """
  Removes an alsoKnownAs URI from an identity.
  """
  def remove_also_known_as(identity_id, uri) do
    with {:ok, identity} <- fetch_identity(identity_id) do
      current = identity.also_known_as || []
      updated = Enum.reject(current, &(&1 == uri))

      identity
      |> Ecto.Changeset.change(also_known_as: updated)
      |> Repo.update()
    end
  end

  # --- Private helpers ---

  defp fetch_identity(identity_id) do
    case Accounts.get_identity(identity_id) do
      nil -> {:error, :identity_not_found}
      identity -> {:ok, identity}
    end
  end

  defp resolve_identity(ap_id) do
    case Repo.one(from(i in Identity, where: i.ap_actor_url == ^ap_id)) do
      nil -> {:error, :identity_not_found}
      identity -> {:ok, identity}
    end
  end

  defp resolve_or_create_identity(ap_id) do
    case Repo.one(from(i in Identity, where: i.ap_actor_url == ^ap_id)) do
      nil ->
        # For now, return an error. In production this would fetch and create.
        {:error, :target_not_found}

      identity ->
        {:ok, identity}
    end
  end

  defp verify_target_exists(target_ap_id) do
    # In production, this would make an HTTP request to fetch the actor.
    # For now, we just verify the URL is well-formed.
    case URI.parse(target_ap_id) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        :ok

      _ ->
        {:error, :invalid_target_url}
    end
  end

  # Validates that the migration target acknowledges this account as
  # one of its prior aliases. Per Mastodon's Move handling, the
  # destination actor's `alsoKnownAs` array MUST contain the source
  # actor URL — otherwise anyone could claim to be the "new home" for
  # any account.
  #
  # If we already know the target (resolved via prior federation) we
  # check the cached `also_known_as` directly. Otherwise we fetch the
  # target actor JSON over HTTPS and inspect its `alsoKnownAs` field
  # before accepting the move.
  defp verify_target_also_known_as(target_ap_id, identity) do
    actor_url = identity.ap_actor_url

    case Repo.one(from(i in Identity, where: i.ap_actor_url == ^target_ap_id)) do
      nil ->
        verify_remote_target_also_known_as(target_ap_id, actor_url)

      target_identity ->
        also_known_as = target_identity.also_known_as || []

        if actor_url in also_known_as do
          :ok
        else
          {:error, :target_not_linked}
        end
    end
  end

  defp verify_remote_target_also_known_as(target_ap_id, source_actor_url) do
    case Hybridsocial.Federation.SignedFetch.get(target_ap_id,
           timeout: 10_000,
           recv_timeout: 10_000,
           follow_redirect: true,
           max_body_length: 100_000
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"alsoKnownAs" => aka}} when is_list(aka) ->
            if source_actor_url in aka do
              :ok
            else
              {:error, :target_not_linked}
            end

          {:ok, _} ->
            {:error, :target_missing_alsoKnownAs}

          _ ->
            {:error, :invalid_target_actor}
        end

      _ ->
        {:error, :target_unreachable}
    end
  end

  defp set_moved_to(identity, target_ap_id) do
    identity
    |> Ecto.Changeset.change(moved_to: target_ap_id)
    |> Repo.update()
  end

  defp publish_move(identity, target_ap_id) do
    activity = %{
      "@context" => ["https://www.w3.org/ns/activitystreams", "https://w3id.org/security/v1"],
      "id" => "#{identity.ap_actor_url}#moves/#{System.system_time(:millisecond)}",
      "type" => "Move",
      "actor" => identity.ap_actor_url,
      "object" => identity.ap_actor_url,
      "target" => target_ap_id,
      "to" => ["https://www.w3.org/ns/activitystreams#Public"],
      "cc" => [identity.followers_url]
    }

    Publisher.publish(activity, identity)
  end

  defp migrate_followers(old_identity_id, new_identity_id) do
    # Find all local followers of the old account
    local_followers =
      Follow
      |> where([f], f.followee_id == ^old_identity_id and f.status == :accepted)
      |> join(:inner, [f], i in assoc(f, :follower))
      |> where([_f, i], is_nil(i.deleted_at))
      |> select([f, _i], f.follower_id)
      |> Repo.all()

    # Create follow relationships with the new account
    Enum.each(local_followers, fn follower_id ->
      case Social.follow(follower_id, new_identity_id) do
        {:ok, _follow} ->
          Logger.info(
            "Migrated follower #{follower_id} from #{old_identity_id} to #{new_identity_id}"
          )

        {:error, reason} ->
          Logger.warning("Failed to migrate follower #{follower_id}: #{inspect(reason)}")
      end
    end)

    {:ok, length(local_followers)}
  end
end
