defmodule Ricqchet.Repo.Migrations.RemoveApiKeyFromTenants do
  use Ecto.Migration

  def change do
    drop_if_exists unique_index(:tenants, [:api_key_hash])
    drop_if_exists unique_index(:tenants, [:api_key_prefix])

    alter table(:tenants) do
      remove :api_key_hash, :binary
      remove :api_key_prefix, :string
    end
  end
end
