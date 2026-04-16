defmodule Hybridsocial.Repo.Migrations.AddDiscoverableToIdentities do
  use Ecto.Migration

  def change do
    alter table(:identities) do
      add :discoverable, :boolean, null: false, default: true
    end
  end
end
