defmodule Ricqchet.Repo.Migrations.CreateTenants do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :api_key_hash, :binary, null: false
      add :status, :string, default: "active"
      add :default_max_retries, :integer, default: 3

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tenants, [:api_key_hash])
  end
end
