defmodule Ricqchet.Repo.Migrations.DefaultUserRoleToViewer do
  use Ecto.Migration

  # Self-hosted OSS: new users default to the least-privileged "viewer" role.
  # Admins are always created explicitly, so "admin" must never be the default.
  def up do
    alter table(:users) do
      modify :role, :string, default: "viewer", null: false
    end
  end

  def down do
    alter table(:users) do
      modify :role, :string, default: "admin", null: false
    end
  end
end
