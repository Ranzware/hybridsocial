defmodule Hybridsocial.Repo.Migrations.AddOnboardedAtToIdentities do
  use Ecto.Migration

  def up do
    alter table(:identities) do
      add :onboarded_at, :utc_datetime_usec
    end

    flush()

    # Backfill: every existing identity is considered already onboarded.
    # New identities created after this migration will have NULL until the
    # user completes (or skips) the first-login onboarding flow.
    execute("UPDATE identities SET onboarded_at = NOW() WHERE onboarded_at IS NULL")
  end

  def down do
    alter table(:identities) do
      remove :onboarded_at
    end
  end
end
