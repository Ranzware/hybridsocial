defmodule Hybridsocial.Repo.Migrations.AuditLogTargetIdToText do
  use Ecto.Migration

  @moduledoc """
  `audit_log.target_id` was created as `uuid` but callers pass
  non-UUID strings too: setting keys ("registration_mode"),
  instance-policy domains ("mastodon.social"), invite codes. Every
  `Moderation.log(..., "setting", "registration_mode", ...)` insert
  was 500ing with Ecto.ChangeError. Widening to text is the smallest
  fix that keeps the existing UUID values intact — UUIDs cast to
  their canonical string form via `::text`.
  """

  def up do
    execute "ALTER TABLE audit_log ALTER COLUMN target_id TYPE text USING target_id::text"
  end

  def down do
    # Only reversible if every current target_id happens to be a valid
    # UUID; otherwise the cast raises. We accept that — the whole
    # point of the forward migration is to hold non-UUID values.
    execute "ALTER TABLE audit_log ALTER COLUMN target_id TYPE uuid USING target_id::uuid"
  end
end
