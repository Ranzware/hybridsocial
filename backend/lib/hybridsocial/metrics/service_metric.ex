defmodule Hybridsocial.Metrics.ServiceMetric do
  @moduledoc """
  One sample of a single metric for a single backing service. Wide,
  thin schema — all metrics from all services share a table because
  the cardinality is tiny (~22 series total) and the read patterns
  are a uniform "give me the last N points for (service, metric)".
  """

  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  schema "service_metrics" do
    field :service, :string
    field :metric, :string
    field :value, :float
    field :inserted_at, :utc_datetime_usec
  end
end
