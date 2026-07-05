defmodule Mix.Tasks.Hybridsocial.ImportPleromaFollows do
  @shortdoc "Import the Pleroma follow graph (remote endpoints + follows)"
  @moduledoc """
  Import the follow graph from a retired Pleroma/Rebased instance. Run
  AFTER `mix hybridsocial.import_pleroma_users`.

      mix hybridsocial.import_pleroma_follows remote_endpoints.jsonl follows.jsonl

  Creates remote identity rows for the remote endpoints referenced by local
  users' follows, then the follow rows themselves. Follows whose endpoints
  aren't present (dropped users) are skipped. Idempotent.

  Source exports:

      -- remote_endpoints.jsonl
      WITH imp AS (SELECT id FROM users WHERE local AND email IS NOT NULL AND ap_id LIKE '%/users/%'),
           refd AS (SELECT following_id AS uid FROM following_relationships WHERE follower_id IN (SELECT id FROM imp)
                    UNION SELECT follower_id FROM following_relationships WHERE following_id IN (SELECT id FROM imp))
      SELECT row_to_json(u) FROM (SELECT id,nickname,ap_id,name,actor_type,public_key,inbox,shared_inbox,follower_address,avatar
        FROM users WHERE local=false AND id IN (SELECT uid FROM refd)) u;

      -- follows.jsonl
      WITH imp AS (SELECT id FROM users WHERE local AND email IS NOT NULL AND ap_id LIKE '%/users/%')
      SELECT row_to_json(f) FROM (SELECT follower_id,following_id,state FROM following_relationships
        WHERE follower_id IN (SELECT id FROM imp) OR following_id IN (SELECT id FROM imp)) f;
  """
  use Mix.Task

  alias Hybridsocial.Migration.PleromaImport

  @requirements ["app.start"]

  @impl Mix.Task
  def run([remotes_path, follows_path]) do
    remotes = read_jsonl(remotes_path)
    Mix.shell().info("Remote endpoints: #{length(remotes)}")
    rs = PleromaImport.import_remote_actors(remotes)
    Mix.shell().info("  imported/skipped=#{rs.ok}  failed=#{rs.failed}")

    follows = read_jsonl(follows_path)
    Mix.shell().info("Follows: #{length(follows)}")
    fs = PleromaImport.import_follows(follows)
    Mix.shell().info("  imported=#{fs.ok}  skipped=#{fs.skipped}")
  end

  def run(_) do
    Mix.raise("Usage: mix hybridsocial.import_pleroma_follows <remotes.jsonl> <follows.jsonl>")
  end

  defp read_jsonl(path) do
    path
    |> File.stream!()
    |> Stream.reject(&(String.trim(&1) == ""))
    |> Stream.map(&Jason.decode!/1)
    |> Enum.to_list()
  end
end
