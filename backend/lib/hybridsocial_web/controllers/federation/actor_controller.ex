defmodule HybridsocialWeb.Federation.ActorController do
  use HybridsocialWeb, :controller

  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Social.Follow
  alias Hybridsocial.Federation.ActorSerializer
  alias Hybridsocial.Federation.OutboxSerializer

  # ActivityPub spec permits either of these two media types for
  # actor + collection JSON. Some clients (notably Pleroma's older
  # versions) request only `application/ld+json`, so we negotiate
  # rather than hardcoding one.
  @ap_content_type "application/activity+json"
  @ld_content_type ~s(application/ld+json; profile="https://www.w3.org/ns/activitystreams")

  def show(conn, %{"id" => id}) do
    case Accounts.get_identity(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Actor not found"})

      identity ->
        actor = ActorSerializer.to_ap(identity)

        conn
        |> put_resp_content_type(negotiated_content_type(conn))
        |> json(actor)
    end
  end

  # Picks the content type to emit based on the Accept header. Falls
  # back to `application/activity+json` (the more common AP type) when
  # nothing matches or the client sent no Accept header.
  defp negotiated_content_type(conn) do
    accept_headers = Plug.Conn.get_req_header(conn, "accept")
    accept = accept_headers |> List.first() |> to_string() |> String.downcase()

    cond do
      String.contains?(accept, "application/ld+json") -> @ld_content_type
      String.contains?(accept, "application/activity+json") -> @ap_content_type
      true -> @ap_content_type
    end
  end

  def followers(conn, %{"id" => id}) do
    case Accounts.get_identity(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Actor not found"})

      identity ->
        base_url = HybridsocialWeb.Endpoint.url()
        collection_url = "#{base_url}/actors/#{identity.id}/followers"

        follower_identities =
          Follow
          |> where([f], f.followee_id == ^identity.id and f.status == :accepted)
          |> join(:inner, [f], i in Identity, on: f.follower_id == i.id)
          |> select([f, i], i)
          |> Repo.all()

        follower_urls =
          Enum.map(follower_identities, fn i ->
            if i.ap_actor_url && !String.starts_with?(i.ap_actor_url, base_url) do
              i.ap_actor_url
            else
              "#{base_url}/actors/#{i.id}"
            end
          end)

        collection = %{
          "@context" => ["https://www.w3.org/ns/activitystreams", "https://w3id.org/security/v1"],
          "id" => collection_url,
          "type" => "OrderedCollection",
          "totalItems" => length(follower_urls),
          "orderedItems" => follower_urls
        }

        conn
        |> put_resp_content_type(negotiated_content_type(conn))
        |> json(collection)
    end
  end

  def following(conn, %{"id" => id}) do
    case Accounts.get_identity(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Actor not found"})

      identity ->
        base_url = HybridsocialWeb.Endpoint.url()
        collection_url = "#{base_url}/actors/#{identity.id}/following"

        following_identities =
          Follow
          |> where([f], f.follower_id == ^identity.id and f.status == :accepted)
          |> join(:inner, [f], i in Identity, on: f.followee_id == i.id)
          |> select([f, i], i)
          |> Repo.all()

        following_urls =
          Enum.map(following_identities, fn i ->
            if i.ap_actor_url && !String.starts_with?(i.ap_actor_url, base_url) do
              i.ap_actor_url
            else
              "#{base_url}/actors/#{i.id}"
            end
          end)

        collection = %{
          "@context" => ["https://www.w3.org/ns/activitystreams", "https://w3id.org/security/v1"],
          "id" => collection_url,
          "type" => "OrderedCollection",
          "totalItems" => length(following_urls),
          "orderedItems" => following_urls
        }

        conn
        |> put_resp_content_type(negotiated_content_type(conn))
        |> json(collection)
    end
  end

  def featured(conn, %{"id" => id}) do
    base_url = HybridsocialWeb.Endpoint.url()

    # Use the schema (not a raw "posts" string source) so Ecto casts
    # the string-form UUID to binary for us. The raw-source query
    # crashed with `Postgrex expected a binary of 16 bytes` when
    # called via the federation route — Mastodon hits this endpoint
    # on every actor lookup.
    pinned =
      from(p in Hybridsocial.Social.Post,
        where: p.identity_id == ^id and p.is_pinned == true and is_nil(p.deleted_at),
        select: p.id,
        order_by: [desc: p.inserted_at]
      )
      |> Repo.all()

    items = Enum.map(pinned, fn post_id -> "#{base_url}/posts/#{post_id}" end)

    conn
    |> put_resp_content_type(@ap_content_type)
    |> json(%{
      "@context" => ["https://www.w3.org/ns/activitystreams", "https://w3id.org/security/v1"],
      "id" => "#{base_url}/actors/#{id}/collections/featured",
      "type" => "OrderedCollection",
      "totalItems" => length(items),
      "orderedItems" => items
    })
  end

  def outbox(conn, %{"id" => id} = params) do
    case Accounts.get_identity(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Actor not found"})

      identity ->
        page =
          case params["page"] do
            nil -> nil
            p when is_binary(p) -> String.to_integer(p)
            p when is_integer(p) -> p
          end

        collection = OutboxSerializer.serialize_outbox(identity, page)

        conn
        |> put_resp_content_type(negotiated_content_type(conn))
        |> json(collection)
    end
  end
end
