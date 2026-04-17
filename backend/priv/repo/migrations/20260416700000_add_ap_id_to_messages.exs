defmodule Hybridsocial.Repo.Migrations.AddApIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :ap_id, :string
    end

    create unique_index(:messages, [:ap_id])
  end
end
