defmodule Ricqchet.Repo.Migrations.UpdateBatchesTextColumns do
  use Ecto.Migration

  def change do
    alter table(:batches) do
      modify :last_error, :text, from: :string
      modify :last_response_body, :text, from: :string
    end
  end
end
