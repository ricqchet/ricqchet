defmodule Ricqchet.Repo.Migrations.CreateApplications do
  use Ecto.Migration

  def change do
    create table(:applications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :status, :string, default: "active", null: false
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:applications, [:tenant_id])
    create index(:applications, [:tenant_id, :status])
  end
end
