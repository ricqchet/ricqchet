defmodule Ricqchet.Repo.Migrations.AddSigningSecretToTenants do
  use Ecto.Migration

  def up do
    # Enable pgcrypto extension for gen_random_bytes
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto"

    # Add column as nullable first
    alter table(:tenants) do
      add :signing_secret, :binary
    end

    flush()

    # Generate signing secrets for existing tenants
    execute """
    UPDATE tenants
    SET signing_secret = gen_random_bytes(32)
    WHERE signing_secret IS NULL
    """

    # Now add NOT NULL constraint
    alter table(:tenants) do
      modify :signing_secret, :binary, null: false
    end
  end

  def down do
    alter table(:tenants) do
      remove :signing_secret
    end
  end
end
