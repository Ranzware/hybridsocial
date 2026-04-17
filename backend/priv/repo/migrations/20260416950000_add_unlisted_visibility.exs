defmodule Hybridsocial.Repo.Migrations.AddUnlistedVisibility do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    # Postgres requires ALTER TYPE ADD VALUE to run outside a
    # transaction; that's what disables the DDL transaction above.
    # Idempotent with `IF NOT EXISTS` so a re-run after partial
    # application doesn't crash.
    execute("ALTER TYPE post_visibility ADD VALUE IF NOT EXISTS 'unlisted'")
  end

  def down do
    # Postgres doesn't support removing enum values. Manual surgery
    # would be needed; deliberately leaving this as a no-op rather
    # than faking a reversal.
    :ok
  end
end
