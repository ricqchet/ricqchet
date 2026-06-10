defmodule Ricqchet.Repo.Migrations.AddApplicationIdToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :application_id, references(:applications, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:messages, [:application_id])
  end
end
