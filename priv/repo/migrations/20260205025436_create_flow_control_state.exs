defmodule Ricqchet.Repo.Migrations.CreateFlowControlState do
  use Ecto.Migration

  def change do
    create table(:flow_control_state, primary_key: false) do
      add :destination_id, references(:destinations, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      # Parallelism tracking
      add :in_flight_count, :integer, default: 0, null: false

      # Rate limiting (sliding window)
      add :window_start, :utc_datetime_usec
      add :request_count, :integer, default: 0, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
