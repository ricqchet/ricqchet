defmodule Ricqchet.Repo.Migrations.AddDestinationIdToMessages do
  use Ecto.Migration

  def change do
    # Drop the old index first (if it exists) before removing the column
    drop_if_exists index(:messages, [:flow_control_key, :status, :scheduled_at])

    alter table(:messages) do
      add :destination_id, references(:destinations, type: :binary_id, on_delete: :nilify_all)
      remove :flow_control_key, :string
    end

    create index(:messages, [:destination_id])
  end
end
