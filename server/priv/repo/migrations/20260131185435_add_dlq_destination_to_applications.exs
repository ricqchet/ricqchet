defmodule Ricqchet.Repo.Migrations.AddDlqDestinationToApplications do
  use Ecto.Migration

  def change do
    alter table(:applications) do
      add :dlq_destination_url, :text
    end
  end
end
