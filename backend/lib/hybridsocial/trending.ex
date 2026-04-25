defmodule Hybridsocial.Trending do
  @moduledoc """
  Trending context. Computes and retrieves trending posts, hashtags, and links.
  Uses precomputed data stored in the trending_data table.
  Supports OpenSearch aggregations when enabled, with PostgreSQL fallback.
  """
  import Ecto.Query

  alias Hybridsocial.Repo
  alias Hybridsocial.Search.TrendingData
  alias Hybridsocial.Social.{Post, Hashtag}
  alias Hybridsocial.Search.OpenSearch

  require Logger

  @default_limit 20
  @max_limit 40
  @half_life_hours 6
  @min_unique_accounts_posts 3

  # Hashtag eligibility:
  #   * `trending_hashtag_window_hours` — how far back to look. Defaults
  #     to 168h (one week) so low-volume instances don't end up with an
  #     empty trending list whenever a 24h window happens to be quiet.
  #   * `trending_hashtag_min_accounts` — how many distinct authors must
  #     have used the tag in that window. Defaults to 2 (rewards broad
  #     usage over a single chatty account). Tiny instances should set
  #     this to 1 via Admin → Settings so any actively-used tag surfaces.
  defp hashtag_window_hours,
    do: Hybridsocial.Config.get("trending_hashtag_window_hours", 168)

  defp hashtag_min_accounts,
    do: Hybridsocial.Config.get("trending_hashtag_min_accounts", 2)

  @doc """
  Computes trending posts based on recent engagement velocity,
  account diversity, and time decay. Stores results in trending_data.
  """
  def compute_trending_posts do
    if search_backend() == "opensearch" do
      case opensearch_compute_trending_posts() do
        :ok -> :ok
        {:error, _reason} -> pg_compute_trending_posts()
      end
    else
      pg_compute_trending_posts()
    end
  end

  @doc """
  Computes trending hashtags based on usage in the last 24 hours.
  """
  def compute_trending_hashtags do
    if search_backend() == "opensearch" do
      case opensearch_compute_trending_hashtags() do
        :ok -> :ok
        {:error, _reason} -> pg_compute_trending_hashtags()
      end
    else
      pg_compute_trending_hashtags()
    end
  end

  @doc """
  Returns precomputed trending posts with limit/offset.
  """
  def get_trending_posts(opts \\ []) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    trending =
      TrendingData
      |> where([t], t.type == "post")
      |> order_by([t], desc: t.score)
      |> limit(^limit)
      |> offset(^offset)
      |> Repo.all()

    post_ids = Enum.map(trending, & &1.target_id)

    # Exclude hidden posts at read time too, not just at compute
    # time — a post that got admin-hidden after trending was computed
    # should disappear from the feed immediately without waiting for
    # the next compute tick (5 min default).
    posts =
      Post
      |> where([p], p.id in ^post_ids)
      |> where([p], is_nil(p.deleted_at))
      |> where([p], is_nil(p.hidden_at))
      |> Repo.all()
      |> Repo.preload(:identity)
      |> Map.new(&{&1.id, &1})

    Enum.map(trending, fn td ->
      %{trending: td, post: Map.get(posts, td.target_id)}
    end)
    |> Enum.filter(fn %{post: post} -> post != nil end)
  end

  @doc """
  Returns precomputed trending hashtags with limit/offset.
  """
  def get_trending_hashtags(opts \\ []) do
    limit = parse_limit(opts)
    offset = parse_offset(opts)

    TrendingData
    |> where([t], t.type == "hashtag")
    |> order_by([t], desc: t.score)
    |> limit(^limit)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc """
  Returns trending links. Placeholder for now.
  """
  def get_trending_links(_opts \\ []) do
    []
  end

  @doc """
  Removes trending_data older than 48 hours.
  """
  def cleanup_old_trending do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-48, :hour)
      |> DateTime.truncate(:microsecond)

    TrendingData
    |> where([t], t.computed_at < ^cutoff)
    |> Repo.delete_all()

    :ok
  end

  # --- OpenSearch Implementations ---

  defp opensearch_compute_trending_posts do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    cutoff = DateTime.add(now, -24, :hour)

    query = %{
      query: %{
        bool: %{
          filter: [
            %{term: %{visibility: "public"}},
            %{range: %{published_at: %{gte: DateTime.to_iso8601(cutoff)}}}
          ]
        }
      },
      aggs: %{
        top_posts: %{
          terms: %{field: "_id", size: 200},
          aggs: %{
            total_engagement: %{
              sum: %{
                script: %{
                  source:
                    "doc['reaction_count'].value + doc['boost_count'].value + doc['reply_count'].value"
                }
              }
            },
            published: %{
              max: %{field: "published_at"}
            }
          }
        }
      },
      size: 0
    }

    case OpenSearch.search("hybridsocial_posts", query, size: 0) do
      {:ok, %{aggregations: %{"top_posts" => %{"buckets" => buckets}}}} ->
        # Clear old trending posts
        TrendingData
        |> where([t], t.type == "post")
        |> Repo.delete_all()

        entries =
          buckets
          |> Enum.map(fn bucket ->
            post_id = bucket["key"]
            engagement = bucket["total_engagement"]["value"] || 0
            published_ms = bucket["published"]["value"] || 0
            published_dt = DateTime.from_unix!(trunc(published_ms / 1000))
            hours_old = DateTime.diff(now, published_dt, :second) / 3600.0
            decay = :math.pow(0.5, hours_old / @half_life_hours)
            score = engagement * decay

            %{post_id: post_id, score: score, engagement: engagement}
          end)
          |> Enum.filter(fn %{engagement: e} -> e >= @min_unique_accounts_posts end)
          |> Enum.sort_by(& &1.score, :desc)
          |> Enum.take(100)

        Enum.each(entries, fn %{post_id: post_id, score: score, engagement: eng} ->
          %TrendingData{}
          |> TrendingData.changeset(%{
            type: "post",
            target_id: post_id,
            score: score,
            computed_at: now,
            metadata: %{engagement: eng}
          })
          |> Repo.insert!()
        end)

        :ok

      {:error, reason} ->
        Logger.warning("OpenSearch trending posts aggregation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp opensearch_compute_trending_hashtags do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    cutoff = DateTime.add(now, -hashtag_window_hours(), :hour)
    min_accounts = hashtag_min_accounts()

    query = %{
      query: %{
        bool: %{
          filter: [
            %{range: %{inserted_at: %{gte: DateTime.to_iso8601(cutoff)}}}
          ]
        }
      },
      aggs: %{
        trending_hashtags: %{
          terms: %{field: "hashtags", size: 100}
        }
      },
      size: 0
    }

    case OpenSearch.search("hybridsocial_posts", query, size: 0) do
      {:ok, %{aggregations: %{"trending_hashtags" => %{"buckets" => buckets}}}} ->
        # Clear old trending hashtags
        TrendingData
        |> where([t], t.type == "hashtag")
        |> Repo.delete_all()

        buckets
        |> Enum.filter(fn bucket -> bucket["doc_count"] >= min_accounts end)
        |> Enum.each(fn bucket ->
          name = bucket["key"]
          post_count = bucket["doc_count"]
          score = post_count * :math.log(post_count + 1)

          %TrendingData{}
          |> TrendingData.changeset(%{
            type: "hashtag",
            target_id: name,
            score: score,
            computed_at: now,
            metadata: %{post_count: post_count}
          })
          |> Repo.insert!()
        end)

        :ok

      {:error, reason} ->
        Logger.warning("OpenSearch trending hashtags aggregation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- PostgreSQL Implementations (fallback) ---

  defp pg_compute_trending_posts do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    cutoff = DateTime.add(now, -24, :hour)

    results =
      Post
      |> where([p], is_nil(p.deleted_at))
      # Admin-hidden posts drop out of Explore/global timelines, so
      # they should drop out of trending too — otherwise a
      # hidden-but-still-engaging post could surface on /explore via
      # the trending row.
      |> where([p], is_nil(p.hidden_at))
      |> where([p], p.visibility == "public")
      |> where([p], p.published_at >= ^cutoff)
      |> join(:left, [p], r in "reactions", on: r.post_id == p.id and r.inserted_at >= ^cutoff)
      |> join(:left, [p, _r], b in "boosts",
        on: b.post_id == p.id and b.inserted_at >= ^cutoff and is_nil(b.deleted_at)
      )
      |> join(:left, [p, _r, _b], rep in "posts",
        on: rep.parent_id == p.id and rep.inserted_at >= ^cutoff and is_nil(rep.deleted_at)
      )
      |> group_by([p, _r, _b, _rep], p.id)
      |> select([p, r, b, rep], %{
        post_id: p.id,
        published_at: p.published_at,
        reaction_count: count(r.id, :distinct),
        boost_count: count(b.id, :distinct),
        reply_count: count(rep.id, :distinct),
        unique_reactors: fragment("COUNT(DISTINCT ?)", r.identity_id),
        unique_boosters: fragment("COUNT(DISTINCT ?)", b.identity_id),
        unique_repliers: fragment("COUNT(DISTINCT ?)", rep.identity_id)
      })
      |> Repo.all()

    # Clear old trending posts
    TrendingData
    |> where([t], t.type == "post")
    |> Repo.delete_all()

    # Compute scores and insert
    trending_entries =
      results
      |> Enum.map(fn row ->
        approx_unique = row.unique_reactors + row.unique_boosters + row.unique_repliers

        total_engagement = row.reaction_count + row.boost_count + row.reply_count
        hours_old = DateTime.diff(now, row.published_at, :second) / 3600.0
        decay = :math.pow(0.5, hours_old / @half_life_hours)
        score = total_engagement * decay * :math.log(max(approx_unique, 1) + 1)

        %{
          row: row,
          score: score,
          approx_unique: approx_unique,
          total_engagement: total_engagement
        }
      end)
      |> Enum.filter(fn %{approx_unique: u} -> u >= @min_unique_accounts_posts end)
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(100)

    Enum.each(trending_entries, fn %{
                                     row: row,
                                     score: score,
                                     total_engagement: eng,
                                     approx_unique: uniq
                                   } ->
      %TrendingData{}
      |> TrendingData.changeset(%{
        type: "post",
        target_id: row.post_id,
        score: score,
        computed_at: now,
        metadata: %{
          engagement: eng,
          unique_accounts: uniq
        }
      })
      |> Repo.insert!()
    end)

    :ok
  end

  defp pg_compute_trending_hashtags do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    window_hours = hashtag_window_hours()
    min_accounts = hashtag_min_accounts()
    cutoff = DateTime.add(now, -window_hours, :hour)

    results =
      Hashtag
      |> join(:inner, [h], ph in "post_hashtags", on: ph.hashtag_id == h.id)
      |> join(:inner, [_h, ph], p in Post,
        on:
          p.id == ph.post_id and p.inserted_at >= ^cutoff and is_nil(p.deleted_at) and
            is_nil(p.hidden_at)
      )
      |> group_by([h, _ph, _p], [h.id, h.name])
      |> select([h, _ph, p], %{
        hashtag_id: h.id,
        name: h.name,
        post_count: count(p.id, :distinct),
        unique_accounts: fragment("COUNT(DISTINCT ?)", p.identity_id)
      })
      |> having(
        [_h, _ph, p],
        fragment("COUNT(DISTINCT ?)", p.identity_id) >= ^min_accounts
      )
      |> Repo.all()

    # Fetch a 7-hour sparkline history for every trending hashtag in
    # one round trip. date_trunc + GROUP BY pairs each hashtag with its
    # per-hour post count over the last 7h; we then reshape into a
    # 7-element array per hashtag, zero-filling buckets with no posts.
    hashtag_ids = Enum.map(results, & &1.hashtag_id)
    history_by_id = fetch_hashtag_history(hashtag_ids, now)

    # Clear old trending hashtags
    TrendingData
    |> where([t], t.type == "hashtag")
    |> Repo.delete_all()

    # Compute scores and insert
    results
    |> Enum.each(fn row ->
      score = row.post_count * :math.log(row.unique_accounts + 1)

      %TrendingData{}
      |> TrendingData.changeset(%{
        type: "hashtag",
        target_id: row.name,
        score: score,
        computed_at: now,
        metadata: %{
          post_count: row.post_count,
          unique_accounts: row.unique_accounts,
          history: Map.get(history_by_id, row.hashtag_id, List.duplicate(0, 7))
        }
      })
      |> Repo.insert!()
    end)

    :ok
  end

  # Returns %{hashtag_id => [h-6, h-5, ..., h-0]} where each entry is the
  # count of distinct posts carrying that hashtag within that hour.
  defp fetch_hashtag_history([], _now), do: %{}

  defp fetch_hashtag_history(hashtag_ids, now) do
    history_cutoff = DateTime.add(now, -7, :hour)

    # Hour ordinals 0..6 where 0 is the oldest bucket we display.
    # Floor `now` to the hour via Unix seconds, then subtract 6h so the
    # last element is the current hour and index 0 is six hours back.
    current_hour_unix = DateTime.to_unix(now) - rem(DateTime.to_unix(now), 3600)
    base_hour = DateTime.from_unix!(current_hour_unix - 6 * 3600)

    # `post_hashtags` is queried as a raw table source (no schema),
    # so Ecto has no type info for `ph.hashtag_id`. Without an
    # explicit `type/2` cast, Postgrex tries to encode the UUID
    # strings as raw 16-byte binaries and crashes. Explicit cast
    # tells it the array is `{:array, Ecto.UUID}`.
    rows =
      Post
      |> join(:inner, [p], ph in "post_hashtags", on: ph.post_id == p.id)
      |> where([p, ph], ph.hashtag_id in type(^hashtag_ids, {:array, Ecto.UUID}))
      |> where([p, _ph], p.inserted_at >= ^history_cutoff and is_nil(p.deleted_at))
      |> group_by([p, ph], [ph.hashtag_id, fragment("date_trunc('hour', ?)", p.inserted_at)])
      |> select([p, ph], %{
        hashtag_id: ph.hashtag_id,
        bucket: fragment("date_trunc('hour', ?)", p.inserted_at),
        count: count(p.id, :distinct)
      })
      |> Repo.all()

    Enum.reduce(rows, %{}, fn row, acc ->
      bucket_index = DateTime.diff(row.bucket, base_hour, :second) |> div(3600)

      if bucket_index in 0..6 do
        series = Map.get(acc, row.hashtag_id) || List.duplicate(0, 7)
        Map.put(acc, row.hashtag_id, List.replace_at(series, bucket_index, row.count))
      else
        acc
      end
    end)
  end

  defp search_backend do
    Hybridsocial.Search.search_backend()
  end

  defp parse_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> min(@max_limit)
    |> max(1)
  end

  defp parse_offset(opts) do
    opts
    |> Keyword.get(:offset, 0)
    |> max(0)
  end
end
