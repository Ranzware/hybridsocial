defmodule Hybridsocial.Repo.Migrations.BackfillSettingCategories do
  use Ecto.Migration

  @moduledoc """
  Settings created before Config.Store learned to infer a category
  from the key prefix all ended up in the "general" bucket. That
  made the tiers / theme / email admin pages show empty forms even
  when values were saved (their filter looks for category = "tiers"
  / "theme" / etc.). Backfill the obvious buckets.
  """

  def up do
    execute "UPDATE instance_settings SET category = 'tiers'   WHERE category = 'general' AND (key LIKE 'tier_%'   OR key LIKE 'tiers_%')"

    execute "UPDATE instance_settings SET category = 'theme'   WHERE category = 'general' AND key LIKE 'theme_%'"

    execute "UPDATE instance_settings SET category = 'email'   WHERE category = 'general' AND key LIKE 'email_%'"

    execute "UPDATE instance_settings SET category = 'apps'    WHERE category = 'general' AND key LIKE 'app_%'"

    execute "UPDATE instance_settings SET category = 'backups' WHERE category = 'general' AND key LIKE 'backup_%'"
  end

  def down, do: :ok
end
