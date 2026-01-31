defmodule Ricqchet.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :api_key_hash, :binary, null: false
      add :api_key_prefix, :string, size: 16, null: false
      add :status, :string, default: "active", null: false
      add :last_used_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec

      add :application_id, references(:applications, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:api_keys, [:api_key_prefix])
    create index(:api_keys, [:application_id])
    create index(:api_keys, [:application_id, :status])
  end
end
