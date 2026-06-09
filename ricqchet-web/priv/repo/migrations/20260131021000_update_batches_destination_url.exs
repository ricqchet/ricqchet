defmodule Ricqchet.Repo.Migrations.UpdateBatchesDestinationUrl do
  use Ecto.Migration

  def change do
    # Match messages table which uses :text for destination_url
    # :string has a 255 char limit which could truncate long URLs
    alter table(:batches) do
      modify :destination_url, :text, from: :string
    end
  end
end
