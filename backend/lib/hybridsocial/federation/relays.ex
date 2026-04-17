defmodule Hybridsocial.Federation.Relays do
  @moduledoc """
  Context for managing ActivityPub relay subscriptions.
  Relays broadcast content to and from other instances.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Federation.Relay

  @doc """
  Subscribes to a relay by sending an AP Follow to the relay inbox.
  Creates a relay record with status "pending".
  """
  def subscribe_to_relay(inbox_url, _admin_id) do
    %Relay{}
    |> Relay.changeset(%{inbox_url: inbox_url, status: "pending"})
    |> Repo.insert()
  end

  @doc """
  Unsubscribes from a relay. Soft-deletes the relay record.
  In production, would also send an Undo{Follow} to the relay inbox.
  """
  def unsubscribe_from_relay(relay_id, _admin_id) do
    case Repo.get(Relay, relay_id) do
      nil ->
        {:error, :not_found}

      relay ->
        Repo.delete(relay)
    end
  end

  @doc """
  Lists all relays.
  """
  def list_relays do
    Relay
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Marks a relay as accepted. Called when we receive an Accept activity
  from the relay in response to our Follow.
  """
  def accept_relay(domain) do
    relay =
      Relay
      |> where([r], fragment("? LIKE '%' || ? || '%'", r.inbox_url, ^domain))
      |> Repo.one()

    case relay do
      nil ->
        {:error, :not_found}

      relay ->
        relay
        |> Relay.changeset(%{status: "accepted"})
        |> Repo.update()
    end
  end

  @doc """
  Processes an Announce activity received from a relay. The relay
  re-publishes content from instances we don't directly federate
  with — typical use case is "Mastodon Relay" instances that fan
  out posts across smaller instances.

  We extract the announced object URL, dereference it through the
  standard inbox path so it gets MRF + content-filter treatment, and
  rely on the inbox's get_post_by_ap_id check to dedupe if we've
  already seen the post via another route.
  """
  def process_relay_announce(activity) do
    case activity do
      %{"actor" => relay_actor, "object" => object_url} when is_binary(object_url) ->
        # Confirm the announcing actor is a registered relay before
        # accepting the announced post — otherwise any actor could
        # spam our inbox with arbitrary URLs.
        if known_relay?(relay_actor) do
          Hybridsocial.Federation.ObjectResolver.resolve(object_url)
        else
          {:error, :unknown_relay}
        end

      _ ->
        {:error, :invalid_announce}
    end
  end

  # Relays in our DB are stored by inbox_url. The relay's actor URL
  # typically lives on the same host (e.g. inbox at
  # https://relay.example/inbox, actor at https://relay.example/actor).
  # Match by host so we don't have to track a second column.
  defp known_relay?(actor_url) when is_binary(actor_url) do
    case URI.parse(actor_url) do
      %URI{host: host} when is_binary(host) and host != "" ->
        host_pattern = "%//#{host}/%"

        Repo.exists?(
          from(r in Relay,
            where: like(r.inbox_url, ^host_pattern) and r.status == "accepted"
          )
        )

      _ ->
        false
    end
  end

  defp known_relay?(_), do: false

  @doc """
  Gets a relay by ID.
  """
  def get_relay(id) do
    Repo.get(Relay, id)
  end
end
