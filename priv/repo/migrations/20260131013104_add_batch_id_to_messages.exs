defmodule Relay.Repo.Migrations.AddBatchIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :batch_id, references(:batches, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:messages, [:batch_id])
  end
end
