defmodule RicqchetWeb.Schemas.Stats.DeliveryStats do
  @moduledoc """
  Schema for delivery performance statistics response.
  """

  use RicqchetWeb.Schema

  defmodule DeliveryTimes do
    @moduledoc false
    use RicqchetWeb.Schema

    OpenApiSpex.schema(%{
      title: "DeliveryTimes",
      type: :object,
      properties: %{
        average_ms: %Schema{
          type: :integer,
          minimum: 0,
          description: "Average delivery time in milliseconds"
        },
        p95_ms: %Schema{
          type: :integer,
          minimum: 0,
          description: "95th percentile delivery time in milliseconds"
        },
        p99_ms: %Schema{
          type: :integer,
          minimum: 0,
          description: "99th percentile delivery time in milliseconds"
        }
      }
    })
  end

  OpenApiSpex.schema(%{
    title: "DeliveryStats",
    description: "Delivery performance statistics",
    type: :object,
    required: [:period, :total_completed, :success_rate, :retry_rate, :delivery_times],
    properties: %{
      period: %Schema{type: :string, description: "Time period for the statistics"},
      total_completed: %Schema{
        type: :integer,
        minimum: 0,
        description: "Total completed deliveries (success + failed)"
      },
      success_rate: %Schema{
        type: :number,
        minimum: 0,
        maximum: 100,
        description: "Percentage of successful deliveries"
      },
      retry_rate: %Schema{
        type: :number,
        minimum: 0,
        maximum: 100,
        description: "Percentage of messages requiring retries"
      },
      delivery_times: DeliveryTimes
    },
    example: %{
      period: "1h",
      total_completed: 1273,
      success_rate: 98.19,
      retry_rate: 12.5,
      delivery_times: %{
        average_ms: 245,
        p95_ms: 890,
        p99_ms: 1450
      }
    }
  })
end
