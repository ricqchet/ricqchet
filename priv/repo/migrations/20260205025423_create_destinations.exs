defmodule Ricqchet.Repo.Migrations.CreateDestinations do
  use Ecto.Migration

  def change do
    create table(:destinations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :destination_url, :string, null: false

      # Flow control settings (nil = unlimited)
      add :parallelism, :integer
      add :rate_limit, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:destinations, [:tenant_id, :destination_url])
    create index(:destinations, [:tenant_id])
  end
end
