defmodule RicqchetWeb.Schemas.Stats.MessageSizeStats do
  @moduledoc """
  Schema for message size statistics response.
  """

  use RicqchetWeb.Schema

  defmodule SizePercentiles do
    @moduledoc false
    use RicqchetWeb.Schema

    OpenApiSpex.schema(%{
      title: "SizePercentiles",
      type: :object,
      properties: %{
        p50: %Schema{type: :integer, minimum: 0, description: "50th percentile (median) in bytes"},
        p95: %Schema{type: :integer, minimum: 0, description: "95th percentile in bytes"},
        p99: %Schema{type: :integer, minimum: 0, description: "99th percentile in bytes"}
      }
    })
  end

  OpenApiSpex.schema(%{
    title: "MessageSizeStats",
    description: "Message payload size statistics",
    type: :object,
    required: [:period, :message_count, :total_bytes, :average_bytes, :percentiles],
    properties: %{
      period: %Schema{type: :string, description: "Time period for the statistics"},
      message_count: %Schema{
        type: :integer,
        minimum: 0,
        description: "Number of messages analyzed"
      },
      total_bytes: %Schema{
        type: :integer,
        minimum: 0,
        description: "Total bytes across all payloads"
      },
      average_bytes: %Schema{
        type: :integer,
        minimum: 0,
        description: "Average payload size in bytes"
      },
      percentiles: SizePercentiles
    },
    example: %{
      period: "1h",
      message_count: 1250,
      total_bytes: 5_242_880,
      average_bytes: 4194,
      percentiles: %{
        p50: 2048,
        p95: 15_360,
        p99: 32_768
      }
    }
  })
end
