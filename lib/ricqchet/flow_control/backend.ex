defmodule Ricqchet.FlowControl.Backend do
  @moduledoc """
  Behaviour for flow control backends.

  Backends implement the slot acquisition and release logic for
  controlling parallelism and rate limits per destination.

  ## Implementing a Backend

  Backends must handle three cases:
  - Return `:ok` when the message can proceed
  - Return `{:delay, seconds}` when limits are exceeded
  - Fail open (return `:ok`) on internal errors to avoid blocking delivery
  """

  @type destination_id :: binary()

  @doc """
  Attempts to acquire a flow control slot for the given destination.

  Returns `:ok` if the message can proceed, or `{:delay, seconds}` if
  limits are exceeded and the message should be rescheduled.
  """
  @callback acquire_slot(
              destination_id :: destination_id(),
              parallelism :: pos_integer() | nil,
              rate_limit :: pos_integer() | nil
            ) :: :ok | {:delay, float()}

  @doc """
  Releases a flow control slot after delivery completes.

  Called regardless of delivery success or failure.
  """
  @callback release_slot(destination_id :: destination_id()) :: :ok
end
