defmodule Hybridsocial.Repo.Migrations.AddMissingPermissions do
  use Ecto.Migration

  @moduledoc """
  The RBAC seed in 20260322900000_create_rbac_tables.exs only registered
  a subset of the `users.*`, `content.*`, and `settings.*` permissions.
  Controllers landed later (reset password, change email, disable 2FA,
  silence, shadow ban, etc.) reference permission names that were never
  inserted, which makes RBAC.has_permission?/2 return false even for
  the Instance Owner role.

  This migration inserts the missing rows and grants them to the roles
  that the seed would have granted them to if they'd been present:

    * users.edit, users.manage, users.moderate   → owner + admin
    * content.manage                              → owner + admin + moderator
    * settings.manage                             → owner + admin
  """

  @missing [
    {"users.edit", "Edit user profile fields", "users", ~w(owner admin)},
    {"users.manage", "Manage user accounts (password, email, 2FA)", "users", ~w(owner admin)},
    {"users.moderate", "Silence, shadow ban, force sensitive", "users",
     ~w(owner admin moderator)},
    {"content.manage", "Manage content beyond deletion", "content", ~w(owner admin moderator)},
    {"settings.manage", "Manage instance settings", "settings", ~w(owner admin)}
  ]

  def up do
    for {name, description, category, role_names} <- @missing do
      perm_id = Ecto.UUID.generate()

      # Upsert permission by name (no-op if it already exists).
      execute("""
      INSERT INTO permissions (id, name, description, category)
      VALUES ('#{perm_id}', '#{name}', '#{escape(description)}', '#{category}')
      ON CONFLICT (name) DO NOTHING
      """)

      for role_name <- role_names do
        rp_id = Ecto.UUID.generate()

        execute("""
        INSERT INTO role_permissions (id, role_id, permission_id)
        SELECT '#{rp_id}', r.id, p.id
          FROM roles r, permissions p
         WHERE r.name = '#{role_name}' AND p.name = '#{name}'
        ON CONFLICT (role_id, permission_id) DO NOTHING
        """)
      end
    end
  end

  def down do
    # Intentional no-op — removing permissions that controllers depend on
    # would silently break production. Roll forward instead.
    :ok
  end

  defp escape(s), do: String.replace(s, "'", "''")
end
