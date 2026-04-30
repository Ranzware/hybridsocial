defmodule Hybridsocial.Repo.Migrations.AddActivityTypeToFederationDeliveries do
  use Ecto.Migration

  def change do
    alter table(:federation_deliveries) do
      # Records the AP type ("Create" / "Update" / "Delete" / "Follow" / "Like"
      # / "Announce" / etc.) at insertion time so the admin throughput chart
      # can break down deliveries by type without re-fetching the activity
      # body. Nullable because pre-existing rows won't have it.
      add :activity_type, :string
    end

    # Hot indexes for the dashboard's queue / throughput / failures queries.
    create index(:federation_deliveries, [:status, :last_attempt_at])
    create index(:federation_deliveries, [:status, :inserted_at])
  end
end
