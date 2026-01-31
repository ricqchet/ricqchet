defmodule Ricqchet.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :password_hash, :string, null: false
      add :status, :string, default: "active", null: false
      add :role, :string, default: "admin", null: false
      add :confirmed_at, :utc_datetime_usec
      add :last_login_at, :utc_datetime_usec
      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:tenant_id, :email])
    create index(:users, [:tenant_id])
    create index(:users, [:tenant_id, :status])
  end
end
