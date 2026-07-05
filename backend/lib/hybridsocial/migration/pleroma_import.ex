defmodule Hybridsocial.Migration.PleromaImport do
  @moduledoc """
  Maps a local user row from a retired Pleroma/Rebased instance onto a
  HybridSocial `Identity`, preserving its ActivityPub identity so remote
  servers keep accepting it after the platform swap.

  The source is a decoded `users`-row map (string keys, as produced by
  `SELECT row_to_json(...)`), which keeps this decoupled from *how* the
  data is read — a JSONL export today, a direct DB read at cutover.

  Two things the source does NOT give us and we reconstruct:

    * Pleroma stores only the RSA **private** key (`keys`) for local
      users; the public key is derived from it here (same encoding our
      native key generation uses).
    * `inbox`/`shared_inbox` are often null because Pleroma computes them
      from the actor URL; we do the same.
  """

  import Ecto.Query
  require Logger

  alias Hybridsocial.Repo
  alias Hybridsocial.Accounts.{Identity, User}
  alias Hybridsocial.Social.{Follow, Post, Posts}
  alias Hybridsocial.Media.MediaFile
  alias Hybridsocial.Federation.ActivityMapper

  @doc """
  Import one Pleroma local-user map. Idempotent: an actor already present
  (matched on `ap_actor_url`) is returned untouched so a run can be
  resumed safely.
  """
  def import_user(%{} = u) do
    with {:ok, attrs} <- to_identity_attrs(u) do
      case Repo.get_by(Identity, ap_actor_url: attrs["ap_actor_url"]) do
        nil ->
          case attrs |> Identity.import_changeset() |> Repo.insert() do
            {:ok, identity} ->
              maybe_create_user_account(identity, u["email"])
              {:ok, identity}

            error ->
              error
          end

        %Identity{} = existing ->
          {:ok, existing}
      end
    end
  end

  # A local Pleroma user needs a HybridSocial User account (login + email) so
  # they can reclaim it via the post-migration password reset. We give it a
  # random unusable password (they set a real one through the reset email)
  # and mark it confirmed since they're a pre-existing user. Users with no
  # email get an identity only — no login row — and are handled manually.
  defp maybe_create_user_account(identity, email) when is_binary(email) and email != "" do
    pw = 24 |> :crypto.strong_rand_bytes() |> Base.url_encode64()

    result =
      %User{identity_id: identity.id}
      |> User.registration_changeset(%{
        "email" => email,
        "password" => pw,
        "password_confirmation" => pw
      })
      |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now())
      |> Ecto.Changeset.put_change(:confirmation_token, nil)
      |> Repo.insert()

    case result do
      {:ok, _user} ->
        :ok

      {:error, cs} ->
        Logger.warning(
          "[pleroma_import] user account failed for #{identity.handle}: #{inspect(cs.errors)}"
        )

        :ok
    end
  end

  defp maybe_create_user_account(_identity, _email), do: :ok

  @doc "Import a list of Pleroma user maps, returning a summary of outcomes."
  def import_users(users) when is_list(users) do
    Enum.reduce(users, %{ok: 0, skipped: 0, failed: []}, fn u, acc ->
      case import_user(u) do
        {:ok, _} ->
          %{acc | ok: acc.ok + 1}

        {:error, reason} ->
          %{acc | failed: [{u["nickname"], summarize_error(reason)} | acc.failed]}
      end
    end)
  end

  @doc """
  Insert a remote (federated) actor referenced by a local user's follow
  graph, so the follow rows have both endpoints. Reuses the source UUID as
  the identity id (like local imports) so follows map by id. No key
  generation, no network fetch — the data comes straight from the source
  DB. Idempotent on ap_actor_url.
  """
  def import_remote_actor(%{"ap_id" => ap} = m) when is_binary(ap) do
    case Repo.get_by(Identity, ap_actor_url: ap) do
      nil ->
        %Identity{}
        |> Ecto.Changeset.cast(
          %{
            id: m["id"],
            type: map_actor_type(m["actor_type"]),
            handle: remote_handle(m["nickname"], ap),
            display_name: truncate(m["name"] || m["nickname"], 50),
            ap_actor_url: ap,
            is_local: false,
            public_key: m["public_key"],
            inbox_url: presence(m["inbox"]) || ap <> "/inbox",
            outbox_url: ap <> "/outbox",
            followers_url: m["follower_address"],
            avatar_url: extract_media_url(m["avatar"])
          },
          [
            :id,
            :type,
            :handle,
            :display_name,
            :ap_actor_url,
            :is_local,
            :public_key,
            :inbox_url,
            :outbox_url,
            :followers_url,
            :avatar_url
          ]
        )
        |> Ecto.Changeset.validate_required([:type, :handle, :ap_actor_url])
        |> Ecto.Changeset.unique_constraint(:handle)
        |> Ecto.Changeset.unique_constraint(:ap_actor_url)
        |> Repo.insert()

      %Identity{} = existing ->
        {:ok, existing}
    end
  rescue
    # DB-level failures (e.g. a stray over-long field) shouldn't abort the
    # whole batch — record and move on.
    e in [Postgrex.Error, DBConnection.ConnectionError] ->
      {:error, Exception.message(e)}
  end

  def import_remote_actor(_), do: {:error, :missing_ap_id}

  def import_remote_actors(list) when is_list(list) do
    Enum.reduce(list, %{ok: 0, failed: 0}, fn m, acc ->
      case import_remote_actor(m) do
        {:ok, _} -> %{acc | ok: acc.ok + 1}
        _ -> %{acc | failed: acc.failed + 1}
      end
    end)
  end

  @doc """
  Import follow rows (`%{"follower_id","following_id","state"}` maps, using
  the source UUIDs which we preserved as identity ids). Both endpoints must
  already exist as identities (local imports + `import_remote_actors`);
  rows referencing a dropped/never-imported endpoint are skipped. Pleroma
  state 2 → accepted, 1 → pending, 3 (rejected) → skipped. Idempotent.
  """
  def import_follows(follows) when is_list(follows) do
    id_set = from(i in Identity, select: i.id) |> Repo.all() |> MapSet.new()

    Enum.reduce(follows, %{ok: 0, skipped: 0}, fn f, acc ->
      fid = f["follower_id"]
      gid = f["following_id"]

      status =
        case f["state"] do
          2 -> :accepted
          1 -> :pending
          _ -> nil
        end

      cond do
        is_nil(status) or fid == gid ->
          %{acc | skipped: acc.skipped + 1}

        not (MapSet.member?(id_set, fid) and MapSet.member?(id_set, gid)) ->
          %{acc | skipped: acc.skipped + 1}

        true ->
          %Follow{}
          |> Follow.changeset(%{follower_id: fid, followee_id: gid, status: status})
          |> Repo.insert(
            on_conflict: {:replace, [:status, :updated_at]},
            conflict_target: [:follower_id, :followee_id]
          )
          |> case do
            {:ok, _} -> %{acc | ok: acc.ok + 1}
            {:error, _} -> %{acc | skipped: acc.skipped + 1}
          end
      end
    end)
  end

  @doc """
  Import local `Note` objects (Pleroma `objects.data` maps) as posts,
  reusing the same AP-Note → post mapping the inbox uses for federated
  content, minus the federation/moderation/notification side-effects.

  `author_map` is `ap_actor_url => identity_id` for the local users (build
  it once with `local_author_map/0`). Notes whose author isn't a local
  import are skipped. Parent links are resolved best-effort at insert and
  finalised by `link_post_threads/0` afterwards (a child may be imported
  before its parent).
  """
  def import_posts(notes, author_map) when is_list(notes) do
    Enum.reduce(notes, %{ok: 0, skipped: 0, failed: []}, fn note, acc ->
      case import_post(note, author_map) do
        {:ok, _} -> %{acc | ok: acc.ok + 1}
        {:skip, _} -> %{acc | skipped: acc.skipped + 1}
        {:error, reason} -> %{acc | failed: [{note["id"], reason} | acc.failed]}
      end
    end)
  end

  def import_post(%{} = note, author_map) do
    author_ap = note["actor"] || note["attributedTo"]

    with author_id when is_binary(author_id) <- Map.get(author_map, author_ap),
         attrs <- ActivityMapper.to_post(note) |> maybe_media_type(note),
         ap_id when is_binary(ap_id) <- attrs["ap_id"],
         nil <- Repo.get_by(Post, ap_id: ap_id) do
      parent_ap_id = attrs["parent_ap_id"]
      parent_id = resolve_parent_id(parent_ap_id)

      insert_attrs =
        attrs
        |> Map.delete("parent_ap_id")
        |> Map.put("identity_id", author_id)
        |> Map.put("parent_ap_id", parent_ap_id)
        |> put_if(parent_id, "parent_id")
        |> Posts.maybe_resolve_root_id()

      %Post{}
      |> Post.create_changeset(insert_attrs, char_limit: 100_000)
      |> maybe_change(:content_html, attrs["content_html"])
      |> maybe_change(:published_at, attrs["published_at"])
      |> Repo.insert()
      |> case do
        {:ok, post} ->
          persist_attachments(note, post, author_id)
          {:ok, post}

        {:error, cs} ->
          {:error, summarize_error(cs)}
      end
    else
      nil -> {:skip, :author_not_local_or_dup}
      %Post{} -> {:skip, :exists}
      _ -> {:skip, :no_ap_id}
    end
  rescue
    e in [Postgrex.Error, DBConnection.ConnectionError] -> {:error, Exception.message(e)}
  end

  @doc "ap_actor_url => identity_id for local (importable) actors."
  def local_author_map do
    from(i in Identity, where: i.is_local == true, select: {i.ap_actor_url, i.id})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Second pass after `import_posts`: link parent_id from parent_ap_id, set
  each post's thread root, and recompute reply counts. One-time bulk SQL.
  """
  def link_post_threads do
    {parents, _} =
      Repo.query!(
        """
        UPDATE posts c SET parent_id = p.id
        FROM posts p
        WHERE c.parent_ap_id = p.ap_id AND c.parent_id IS NULL AND c.parent_ap_id IS NOT NULL
        """,
        []
      )
      |> then(&{&1.num_rows, &1})

    Repo.query!(
      """
      WITH RECURSIVE roots AS (
        SELECT id, id AS root FROM posts WHERE parent_id IS NULL
        UNION ALL
        SELECT p.id, r.root FROM posts p JOIN roots r ON p.parent_id = r.id
      )
      UPDATE posts SET root_id = roots.root
      FROM roots WHERE posts.id = roots.id AND posts.id <> roots.root
      """,
      []
    )

    Repo.query!(
      """
      UPDATE posts pp SET reply_count = sub.n
      FROM (SELECT parent_id AS id, count(*) AS n FROM posts
            WHERE parent_id IS NOT NULL AND deleted_at IS NULL GROUP BY parent_id) sub
      WHERE pp.id = sub.id
      """,
      []
    )

    %{parents_linked: parents}
  end

  # A caption-less post with an attachment is a "media" post (content
  # optional); to_post labels every Note "text", which would reject the
  # blank content. Only reclassify when there's actually media.
  defp maybe_media_type(attrs, note) do
    blank? = String.trim(attrs["content"] || "") == ""
    has_media? = note["attachment"] |> List.wrap() |> Enum.any?(&(attachment_url(&1) != nil))

    if blank? and has_media?, do: Map.put(attrs, "post_type", "media"), else: attrs
  end

  defp resolve_parent_id(nil), do: nil

  defp resolve_parent_id(parent_ap_id) do
    case Repo.get_by(Post, ap_id: parent_ap_id) do
      %Post{id: id} -> id
      _ -> nil
    end
  end

  defp put_if(attrs, nil, _key), do: attrs
  defp put_if(attrs, val, key), do: Map.put(attrs, key, val)

  defp maybe_change(cs, _field, nil), do: cs
  defp maybe_change(cs, field, val), do: Ecto.Changeset.put_change(cs, field, val)

  defp persist_attachments(note, post, author_id) do
    note["attachment"]
    |> List.wrap()
    |> Enum.each(fn att ->
      url = attachment_url(att)
      domain = if is_binary(url), do: ActivityMapper.extract_domain(url), else: nil

      if is_binary(url) and is_binary(domain) do
        %MediaFile{}
        |> MediaFile.remote_changeset(%{
          identity_id: author_id,
          post_id: post.id,
          content_type: attachment_media_type(att) || "application/octet-stream",
          remote_url: url,
          remote_origin_domain: domain,
          alt_text: att["name"],
          width: att["width"],
          height: att["height"],
          blurhash: att["blurhash"],
          metadata: %{"ap_type" => att["type"]}
        })
        |> Repo.insert()
      end
    end)
  end

  # Pleroma stores an attachment's url as an array of Link objects;
  # Mastodon as a plain string. Handle both.
  defp attachment_url(%{"url" => u}) when is_binary(u), do: u
  defp attachment_url(%{"url" => [%{"href" => h} | _]}) when is_binary(h), do: h
  defp attachment_url(%{"href" => h}) when is_binary(h), do: h
  defp attachment_url(_), do: nil

  defp attachment_media_type(%{"url" => [%{"mediaType" => mt} | _]}) when is_binary(mt), do: mt
  defp attachment_media_type(%{"mediaType" => mt}) when is_binary(mt), do: mt
  defp attachment_media_type(_), do: nil

  # --- mapping ---------------------------------------------------------

  defp to_identity_attrs(%{"ap_id" => ap_id} = u) when is_binary(ap_id) do
    case derive_public_key(u["keys"]) do
      {:ok, public_pem} ->
        origin = origin_of(ap_id)

        {:ok,
         %{
           "id" => u["id"],
           "type" => map_actor_type(u["actor_type"]),
           "handle" => u["nickname"],
           "display_name" => truncate(u["name"] || u["nickname"], 50),
           "bio" => truncate(u["raw_bio"] || strip_html(u["bio"]), 500),
           "ap_actor_url" => ap_id,
           "public_key" => public_pem,
           "private_key" => u["keys"],
           "inbox_url" => presence(u["inbox"]) || ap_id <> "/inbox",
           "outbox_url" => ap_id <> "/outbox",
           "followers_url" => u["follower_address"],
           "following_url" => u["following_address"],
           "featured_url" => u["featured_address"],
           "shared_inbox_url" => presence(u["shared_inbox"]) || origin <> "/inbox",
           "avatar_url" => extract_media_url(u["avatar"]),
           "header_url" => extract_media_url(u["banner"]),
           "is_locked" => u["is_locked"] || false,
           "discoverable" => u["is_discoverable"] || false,
           "also_known_as" => u["also_known_as"] || [],
           "birthday" => u["birthday"],
           "location" => u["location"],
           "metadata" => %{}
         }}

      {:error, reason} ->
        {:error, {:key_derivation, reason}}
    end
  end

  defp to_identity_attrs(_), do: {:error, :missing_ap_id}

  # Pleroma actor types → our internal types.
  defp map_actor_type("Service"), do: "bot"
  defp map_actor_type("Application"), do: "bot"
  defp map_actor_type("Group"), do: "group"
  defp map_actor_type("Organization"), do: "organization"
  defp map_actor_type(_), do: "user"

  @doc """
  Derive the SubjectPublicKeyInfo PEM from an RSA private-key PEM, matching
  the encoding our native key generation produces.
  """
  def derive_public_key(private_pem) when is_binary(private_pem) do
    case :public_key.pem_decode(private_pem) do
      [entry | _] ->
        priv = :public_key.pem_entry_decode(entry)
        # RSAPrivateKey: {:RSAPrivateKey, version, modulus, publicExponent, ...}
        rsa_public = {:RSAPublicKey, elem(priv, 2), elem(priv, 3)}
        pub_entry = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, rsa_public)
        {:ok, :public_key.pem_encode([pub_entry])}

      [] ->
        {:error, :empty_pem}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def derive_public_key(_), do: {:error, :no_private_key}

  # --- helpers ---------------------------------------------------------

  defp origin_of(url) do
    uri = URI.parse(url)
    "#{uri.scheme}://#{uri.host}"
  end

  # Remote handles must be globally unique in HybridSocial (unlike Pleroma,
  # where they're scoped by domain). Suffix the source nickname with a short
  # hash of the actor URL so two remotes named "bob" don't collide.
  defp remote_handle(nickname, ap_id) do
    base =
      (nickname || "user")
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> String.slice(0, 24)

    hash = :crypto.hash(:sha256, ap_id) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    "#{base}_#{hash}"
  end

  defp extract_media_url(%{"url" => [%{"href" => href} | _]}) when is_binary(href), do: href
  defp extract_media_url(%{"url" => href}) when is_binary(href), do: href
  defp extract_media_url(_), do: nil

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(s) when is_binary(s), do: s
  defp presence(_), do: nil

  defp strip_html(nil), do: ""
  defp strip_html(s) when is_binary(s), do: String.replace(s, ~r/<[^>]*>/, "")

  defp truncate(nil, _), do: ""
  defp truncate(s, max) when is_binary(s), do: String.slice(s, 0, max)

  defp summarize_error(%Ecto.Changeset{} = cs) do
    Enum.map_join(cs.errors, "; ", fn {field, {msg, _}} -> "#{field} #{msg}" end)
  end

  defp summarize_error(other), do: inspect(other)

  @doc "How many local actors have already been imported."
  def imported_count do
    from(i in Identity, where: i.is_local == true and not is_nil(i.private_key))
    |> Repo.aggregate(:count)
  end
end
