defmodule Relay.Repo.Migrations.AddApiKeyPrefixToTenants do
  use Ecto.Migration

  def change do
    alter table(:tenants) do
      # Non-secret prefix of the API key for O(1) lookup
      # Format: first 8 characters of the base64-encoded key
      add :api_key_prefix, :string, size: 16
    end

    create unique_index(:tenants, [:api_key_prefix])
  end
end
