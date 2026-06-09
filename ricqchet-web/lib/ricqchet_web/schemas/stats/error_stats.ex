defmodule RicqchetWeb.Schemas.Stats.ErrorStats do
  @moduledoc """
  Schema for error breakdown statistics response.
  """

  use RicqchetWeb.Schema

  defmodule FailingDestination do
    @moduledoc false
    use RicqchetWeb.Schema

    OpenApiSpex.schema(%{
      title: "FailingDestination",
      type: :object,
      properties: %{
        url: %Schema{type: :string, format: :uri, description: "Destination URL"},
        count: %Schema{type: :integer, minimum: 0, description: "Number of failures"}
      }
    })
  end

  OpenApiSpex.schema(%{
    title: "ErrorStats",
    description: "Error breakdown statistics",
    type: :object,
    required: [:period, :total_errors, :by_type, :by_status_code, :top_failing_destinations],
    properties: %{
      period: %Schema{type: :string, description: "Time period for the statistics"},
      total_errors: %Schema{type: :integer, minimum: 0, description: "Total failed messages"},
      by_type: %Schema{
        type: :object,
        additionalProperties: %Schema{type: :integer},
        description:
          "Error counts by type (timeout, connection_refused, http_5xx, http_4xx, ssl_error, dns_error, other)"
      },
      by_status_code: %Schema{
        type: :object,
        additionalProperties: %Schema{type: :integer},
        description: "Error counts by HTTP status code"
      },
      top_failing_destinations: %Schema{
        type: :array,
        items: FailingDestination,
        description: "Destinations with most failures"
      }
    },
    example: %{
      period: "1h",
      total_errors: 23,
      by_type: %{
        timeout: 12,
        connection_refused: 5,
        http_5xx: 4,
        http_4xx: 2
      },
      by_status_code: %{
        "500" => 3,
        "502" => 1,
        "400" => 1,
        "401" => 1
      },
      top_failing_destinations: [
        %{url: "https://api.example.com/webhook", count: 8},
        %{url: "https://slow.example.com/events", count: 5}
      ]
    }
  })
end
