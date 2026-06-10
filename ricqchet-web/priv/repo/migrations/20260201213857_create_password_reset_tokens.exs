defmodule Ricqchet.Repo.Migrations.CreatePasswordResetTokens do
  use Ecto.Migration

  def change do
    create table(:password_reset_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token_hash, :string, null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:password_reset_tokens, [:token_hash])
    create index(:password_reset_tokens, [:user_id])
  end
end
