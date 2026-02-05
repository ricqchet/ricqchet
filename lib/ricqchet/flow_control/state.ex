defmodule Ricqchet.FlowControl.State do
  @moduledoc """
  Schema for flow control runtime state.

  Tracks per-destination state:
  - `in_flight_count` - Number of currently dispatched messages
  - `window_start` - Start of current rate limit window
  - `request_count` - Requests made in current window
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:destination_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "flow_control_state" do
    field :in_flight_count, :integer, default: 0
    field :window_start, :utc_datetime_usec
    field :request_count, :integer, default: 0

    belongs_to :destination, Ricqchet.FlowControl.Destination,
      foreign_key: :destination_id,
      references: :id,
      define_field: false

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(state, attrs) do
    state
    |> cast(attrs, [:destination_id, :in_flight_count, :window_start, :request_count])
    |> validate_required([:destination_id])
    |> validate_number(:in_flight_count, greater_than_or_equal_to: 0)
    |> validate_number(:request_count, greater_than_or_equal_to: 0)
  end
end
