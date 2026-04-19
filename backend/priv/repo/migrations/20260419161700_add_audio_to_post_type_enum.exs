defmodule Hybridsocial.Repo.Migrations.AddAudioToPostTypeEnum do
  use Ecto.Migration

  # ALTER TYPE ... ADD VALUE is not transactional in Postgres, so
  # run this migration outside the DDL transaction. Otherwise Ecto
  # wraps the whole migration in BEGIN/COMMIT and Postgres rejects it.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute("ALTER TYPE post_type ADD VALUE IF NOT EXISTS 'audio'")
  end

  def down do
    # Postgres has no DROP VALUE for enums. Rolling back would need
    # to recreate the enum and rewrite every row referencing the
    # removed value — not worth automating. Document the manual
    # rollback in the release notes instead.
    :ok
  end
end
