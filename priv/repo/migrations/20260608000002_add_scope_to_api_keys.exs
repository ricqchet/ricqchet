defmodule Ricqchet.Repo.Migrations.AddScopeToApiKeys do
  use Ecto.Migration

  # Adds the `scope` column to api_keys. The `default: "relay"` backfills every
  # existing row to the full relay scope, so all keys minted before this change
  # keep their current behavior. On PostgreSQL 11+ this is a metadata-only ALTER
  # (no table rewrite/lock), so it is safe for a single pre-boot migration.
  #
  # IMPORTANT: rolling this back DROPS the column, which makes the old code treat
  # every key as full relay access again — any key deliberately created as
  # `subscribe` would silently regain the full relay surface. Prefer fixing
  # forward; if you must roll back, revoke or rotate-to-relay any subscribe keys
  # first. See docs/authentication.md.
  def change do
    alter table(:api_keys) do
      add :scope, :string, null: false, default: "relay"
    end
  end
end
