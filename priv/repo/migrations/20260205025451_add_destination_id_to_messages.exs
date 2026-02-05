defmodule Ricqchet.Repo.Migrations.AddDestinationIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :destination_id, references(:destinations, type: :binary_id, on_delete: :nilify_all)
      remove :flow_control_key
    end

    drop index(:messages, [:flow_control_key, :status, :scheduled_at])
    create index(:messages, [:destination_id])
  end
end
