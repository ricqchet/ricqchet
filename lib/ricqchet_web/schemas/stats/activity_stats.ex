defmodule RicqchetWeb.Schemas.Stats.ActivityStats do
  @moduledoc """
  Schema for activity feed response.
  """

  use RicqchetWeb.Schema

  defmodule ActivityItem do
    @moduledoc false
    use RicqchetWeb.Schema

    OpenApiSpex.schema(%{
      title: "ActivityItem",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Message ID"},
        destination_url: %Schema{type: :string, format: :uri, description: "Destination URL"},
        status: %Schema{
          type: :string,
          enum: ["pending", "dispatched", "delivered", "failed"],
          description: "Current status"
        },
        attempts: %Schema{type: :integer, minimum: 0, description: "Number of delivery attempts"},
        last_error: %Schema{
          type: :string,
          nullable: true,
          description: "Last error message if failed"
        },
        last_response_status: %Schema{
          type: :integer,
          nullable: true,
          description: "Last HTTP response status"
        },
        payload_size_bytes: %Schema{
          type: :integer,
          nullable: true,
          description: "Payload size in bytes"
        },
        application_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "Associated application ID"
        },
        created_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the message was created"
        },
        completed_at: %Schema{
          type: :string,
          format: :"date-time",
          nullable: true,
          description: "When delivery completed"
        }
      }
    })
  end

  defmodule ActivityMeta do
    @moduledoc false
    use RicqchetWeb.Schema

    OpenApiSpex.schema(%{
      title: "ActivityMeta",
      type: :object,
      properties: %{
        has_more: %Schema{type: :boolean, description: "Whether more results are available"},
        next_cursor: %Schema{
          type: :string,
          nullable: true,
          description: "Cursor for fetching next page"
        }
      }
    })
  end

  OpenApiSpex.schema(%{
    title: "ActivityStats",
    description: "Recent message activity",
    type: :object,
    required: [:period, :data, :meta],
    properties: %{
      period: %Schema{type: :string, description: "Time period for the activity"},
      data: %Schema{
        type: :array,
        items: ActivityItem,
        description: "List of recent messages"
      },
      meta: ActivityMeta
    },
    example: %{
      period: "1h",
      data: [
        %{
          id: "550e8400-e29b-41d4-a716-446655440000",
          destination_url: "https://api.example.com/webhook",
          status: "delivered",
          attempts: 1,
          last_error: nil,
          last_response_status: 200,
          payload_size_bytes: 1024,
          application_id: "660e8400-e29b-41d4-a716-446655440001",
          created_at: "2026-01-31T10:00:00Z",
          completed_at: "2026-01-31T10:00:02Z"
        }
      ],
      meta: %{
        has_more: true,
        next_cursor: "eyJpbnNlcnRlZF9hdCI6..."
      }
    }
  })
end
