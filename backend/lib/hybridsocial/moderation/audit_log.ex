defmodule Hybridsocial.Moderation.AuditLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "audit_log" do
    field :action, :string
    field :target_type, :string
    # `:string` rather than `:binary_id` because callers legitimately
    # pass non-UUID identifiers here — setting keys, instance-policy
    # domains, invite codes. UUID targets (identity, post, report,
    # …) still round-trip cleanly as their canonical string form.
    field :target_id, :string
    field :details, :map, default: %{}
    field :ip_address, :string
    field :created_at, :utc_datetime_usec

    belongs_to :actor, Hybridsocial.Accounts.Identity, type: :binary_id
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:actor_id, :action, :target_type, :target_id, :details, :ip_address])
    |> validate_required([:action])
    |> put_change(:created_at, DateTime.utc_now())
  end
end
