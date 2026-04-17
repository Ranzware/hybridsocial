defmodule Hybridsocial.Repo.Migrations.AddRemoteUrlToMedia do
  use Ecto.Migration

  # Federated posts arrive with attachment URLs pointing at the
  # remote instance. We persist those URLs (rather than discarding
  # them as we do today) so the proxy controller can dereference
  # them on demand. `remote_origin_domain` is denormalized at
  # write time so the proxy can short-circuit a federation
  # block-list check without parsing the URL on every request.
  def change do
    alter table(:media) do
      add :remote_url, :text
      add :remote_origin_domain, :string
    end

    create index(:media, [:remote_origin_domain],
             where: "remote_origin_domain IS NOT NULL",
             name: :media_remote_origin_domain_idx
           )
  end
end
