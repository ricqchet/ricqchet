defmodule Ricqchet.Repo.Migrations.AddDestinationIdToMessages do
  use Ecto.Migration

  @moduledoc """
  Replaces flow_control_key with destination_id foreign key.

  Note: This migration assumes no existing messages need flow_control_key
  data preserved. For production systems with existing data, consider
  adding a data migration step to:
  1. Parse flow_control_key format ("tenant_id:destination_url")
  2. Create destination records from existing keys
  3. Update messages with destination_id
  4. Then remove flow_control_key
  """

  def change do
    # Drop the old index first (if it exists) before removing the column
    drop_if_exists index(:messages, [:flow_control_key, :status, :scheduled_at])

    alter table(:messages) do
      # We use on_delete: :nilify_all so that if a destination is ever deleted,
      # existing messages are preserved with destination_id set to NULL.
      # Messages with NULL destination_id bypass flow control, which is handled
      # explicitly in FlowControl.acquire_slot/1.
      add :destination_id, references(:destinations, type: :binary_id, on_delete: :nilify_all)
      remove :flow_control_key, :string
    end

    # Basic index for foreign key lookups
    create index(:messages, [:destination_id])

    # Composite index for efficient pending message queries by destination
    create index(:messages, [:destination_id, :status, :scheduled_at],
             where: "status = 'pending'"
           )
  end
end
