defmodule RicqchetWeb.Schemas.Stats.DestinationStats do
  @moduledoc """
  Schema for destination metrics response.
  """

  use RicqchetWeb.Schema

  defmodule DestinationMetric do
    @moduledoc false
    use RicqchetWeb.Schema

    OpenApiSpex.schema(%{
      title: "DestinationMetric",
      type: :object,
      properties: %{
        url: %Schema{type: :string, format: :uri, description: "Destination URL"},
        volume: %Schema{type: :integer, minimum: 0, description: "Total messages sent"},
        success_rate: %Schema{
          type: :number,
          minimum: 0,
          maximum: 100,
          description: "Percentage of successful deliveries"
        },
        avg_response_time_ms: %Schema{
          type: :integer,
          minimum: 0,
          description: "Average response time in milliseconds"
        }
      }
    })
  end

  OpenApiSpex.schema(%{
    title: "DestinationStats",
    description: "Per-destination metrics",
    type: :object,
    required: [:period, :destinations],
    properties: %{
      period: %Schema{type: :string, description: "Time period for the statistics"},
      destinations: %Schema{
        type: :array,
        items: DestinationMetric,
        description: "List of destination metrics ordered by volume"
      }
    },
    example: %{
      period: "1h",
      destinations: [
        %{
          url: "https://api.example.com/webhook",
          volume: 450,
          success_rate: 99.3,
          avg_response_time_ms: 180
        },
        %{
          url: "https://other.example.com/events",
          volume: 230,
          success_rate: 97.8,
          avg_response_time_ms: 320
        }
      ]
    }
  })
end
