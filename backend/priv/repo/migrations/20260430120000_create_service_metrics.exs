defmodule Hybridsocial.Repo.Migrations.CreateServiceMetrics do
  use Ecto.Migration

  def change do
    create table(:service_metrics, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :service, :string, null: false
      add :metric, :string, null: false
      add :value, :float, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    # Hot path: dashboard reads "last N hours of (service, metric)".
    create index(:service_metrics, [:service, :metric, :inserted_at])

    # Partial index for the dashboard summary, which always wants the
    # last hour. Far cheaper than the full index for that lookup.
    execute(
      """
      CREATE INDEX service_metrics_recent_idx
        ON service_metrics (service, metric, inserted_at DESC)
        WHERE inserted_at > now() - interval '2 hours'
      """,
      "DROP INDEX IF EXISTS service_metrics_recent_idx"
    )
  end
end
