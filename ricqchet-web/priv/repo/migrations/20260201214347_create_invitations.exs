defmodule Ricqchet.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :role, :string, null: false, default: "member"
      add :status, :string, null: false, default: "pending"
      add :token_hash, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :accepted_at, :utc_datetime_usec

      add :tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create index(:invitations, [:tenant_id])
    create index(:invitations, [:token_hash])
    create index(:invitations, [:email])

    # Unique constraint on pending invitations per tenant
    create unique_index(:invitations, [:email, :tenant_id],
             where: "status = 'pending'",
             name: :invitations_email_tenant_id_index
           )
  end
end
