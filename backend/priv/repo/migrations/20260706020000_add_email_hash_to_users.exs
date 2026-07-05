defmodule Hybridsocial.Repo.Migrations.AddEmailHashToUsers do
  use Ecto.Migration

  # The `email` column is now encrypted at rest (randomized ciphertext), so
  # it can no longer be searched or unique-constrained directly. `email_hash`
  # is a deterministic blind index (keyed HMAC of the normalized email) that
  # carries login lookups + uniqueness. Backfilled by
  # `mix hybridsocial.encrypt_existing_data` for pre-existing installs; on a
  # fresh instance every write sets it via the changeset.

  def up do
    alter table(:users) do
      add :email_hash, :string
    end

    # Nullable during backfill; Postgres treats NULLs as distinct so this
    # doesn't collide with not-yet-backfilled rows.
    create unique_index(:users, [:email_hash], name: :users_email_hash_index)
  end

  def down do
    drop index(:users, [:email_hash], name: :users_email_hash_index)

    alter table(:users) do
      remove :email_hash
    end
  end
end
