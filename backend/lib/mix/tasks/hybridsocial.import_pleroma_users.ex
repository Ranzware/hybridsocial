defmodule Mix.Tasks.Hybridsocial.ImportPleromaUsers do
  @shortdoc "Import local users from a Pleroma/Rebased JSONL export"
  @moduledoc """
  Import local users from a retired Pleroma/Rebased instance, preserving
  their ActivityPub identity (URI + keys) so federation survives the swap.

      mix hybridsocial.import_pleroma_users path/to/users.jsonl

  Each line of the file is one JSON object as produced on the source box:

      psql -d <db> -tA -c "SELECT row_to_json(u) FROM (
        SELECT id, nickname, ap_id, name, bio, raw_bio, keys,
               follower_address, following_address, featured_address,
               inbox, shared_inbox, actor_type, email::text AS email,
               avatar, banner, fields, also_known_as, is_locked,
               is_discoverable, birthday, location
        FROM users
        WHERE local = true AND email IS NOT NULL AND ap_id LIKE '%/users/%'
      ) u" > users.jsonl

  Idempotent — safe to re-run; already-imported actors (matched on
  ap_actor_url) are left untouched.
  """
  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run([path]) do
    users =
      path
      |> File.stream!()
      |> Stream.reject(&(String.trim(&1) == ""))
      |> Stream.map(&Jason.decode!/1)
      |> Enum.to_list()

    Mix.shell().info("Read #{length(users)} users from #{path}")

    summary = Hybridsocial.Migration.PleromaImport.import_users(users)

    Mix.shell().info("Imported/skipped: #{summary.ok}   Failed: #{length(summary.failed)}")

    summary.failed
    |> Enum.reverse()
    |> Enum.each(fn {nick, err} -> Mix.shell().error("  FAIL #{nick}: #{err}") end)

    Mix.shell().info(
      "Total local actors now present: #{Hybridsocial.Migration.PleromaImport.imported_count()}"
    )
  end

  def run(_), do: Mix.raise("Usage: mix hybridsocial.import_pleroma_users <file.jsonl>")
end
