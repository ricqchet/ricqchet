defmodule Ricqchet.Repo.Migrations.AddPayloadSizeBytesToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :payload_size_bytes, :integer
    end

    # Backfill existing records
    execute """
            UPDATE messages
            SET payload_size_bytes = octet_length(payload)
            WHERE payload IS NOT NULL AND payload_size_bytes IS NULL
            """,
            ""
  end
end
