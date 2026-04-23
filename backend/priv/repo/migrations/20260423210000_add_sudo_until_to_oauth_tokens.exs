defmodule Hybridsocial.Repo.Migrations.AddSudoUntilToOauthTokens do
  use Ecto.Migration

  def change do
    alter table(:oauth_tokens) do
      add :sudo_until, :utc_datetime_usec
    end
  end
end
