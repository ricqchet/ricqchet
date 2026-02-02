defmodule Ricqchet.Repo.Migrations.AddStatsIndexes do
  use Ecto.Migration

  def change do
    # For time-range queries on completed messages (delivery stats, performance)
    create index(:messages, [:tenant_id, :completed_at], where: "completed_at IS NOT NULL")

    # For destination stats grouping
    create index(:messages, [:tenant_id, :destination_url, :completed_at],
             where: "completed_at IS NOT NULL"
           )

    # For activity feed (recent messages by insertion time)
    create index(:messages, [:tenant_id, :inserted_at])
  end
end
