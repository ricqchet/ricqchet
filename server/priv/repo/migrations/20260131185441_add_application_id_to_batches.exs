defmodule Ricqchet.Repo.Migrations.AddApplicationIdToBatches do
  use Ecto.Migration

  def change do
    alter table(:batches) do
      add :application_id, references(:applications, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:batches, [:application_id])
  end
end
