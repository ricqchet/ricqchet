defmodule RicqchetWeb.Schemas.Stats.MessageStats do
  @moduledoc """
  Schema for message count statistics response.
  """

  use RicqchetWeb.Schema

  defmodule StatusCounts do
    @moduledoc false
    use RicqchetWeb.Schema

    OpenApiSpex.schema(%{
      title: "StatusCounts",
      type: :object,
      properties: %{
        pending: %Schema{type: :integer, minimum: 0, description: "Messages awaiting delivery"},
        dispatched: %Schema{
          type: :integer,
          minimum: 0,
          description: "Messages currently being delivered"
        },
        delivered: %Schema{
          type: :integer,
          minimum: 0,
          description: "Successfully delivered messages"
        },
        failed: %Schema{type: :integer, minimum: 0, description: "Permanently failed messages"}
      }
    })
  end

  OpenApiSpex.schema(%{
    title: "MessageStats",
    description: "Message counts by status",
    type: :object,
    required: [:period, :counts, :total],
    properties: %{
      period: %Schema{type: :string, description: "Time period for the statistics"},
      counts: StatusCounts,
      total: %Schema{type: :integer, minimum: 0, description: "Total messages in period"}
    },
    example: %{
      period: "1h",
      counts: %{
        pending: 42,
        dispatched: 15,
        delivered: 1250,
        failed: 23
      },
      total: 1330
    }
  })
end
