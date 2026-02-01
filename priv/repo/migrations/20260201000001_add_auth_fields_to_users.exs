defmodule Ricqchet.Repo.Migrations.AddAuthFieldsToUsers do
  use Ecto.Migration

  def change do
    # Make email globally unique instead of unique per tenant
    drop unique_index(:users, [:tenant_id, :email])
    create unique_index(:users, [:email])

    alter table(:users) do
      add :token_version, :integer, default: 1, null: false
    end
  end
end
