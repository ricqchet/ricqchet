defmodule RicqchetWeb.Schemas.Message do
  @moduledoc """
  Schema for message resource with delivery status.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "Message",
    description: "A queued message with delivery status and metadata",
    type: :object,
    required: [:id, :status, :destination_url, :method, :attempts, :max_retries, :created_at],
    properties: %{
      id: %Schema{
        type: :string,
        format: :uuid,
        description: "Unique message identifier"
      },
      status: %Schema{
        type: :string,
        enum: ["pending", "dispatched", "delivered", "failed"],
        description: "Current delivery status"
      },
      destination_url: %Schema{
        type: :string,
        format: :uri,
        description: "Target URL for message delivery"
      },
      method: %Schema{
        type: :string,
        enum: ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
        description: "HTTP method for delivery"
      },
      attempts: %Schema{
        type: :integer,
        minimum: 0,
        description: "Number of delivery attempts made"
      },
      max_retries: %Schema{
        type: :integer,
        minimum: 0,
        description: "Maximum retry attempts allowed"
      },
      created_at: %Schema{
        type: :string,
        format: :"date-time",
        description: "Timestamp when message was created"
      },
      scheduled_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Scheduled delivery time (if delayed)"
      },
      dispatched_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Timestamp when delivery was dispatched"
      },
      completed_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Timestamp when delivery completed (success or final failure)"
      },
      last_error: %Schema{
        type: :string,
        nullable: true,
        description: "Error message from last failed attempt"
      },
      last_response_status: %Schema{
        type: :integer,
        nullable: true,
        description: "HTTP status code from last delivery attempt"
      }
    },
    example: %{
      id: "550e8400-e29b-41d4-a716-446655440000",
      status: "delivered",
      destination_url: "https://example.com/webhook",
      method: "POST",
      attempts: 1,
      max_retries: 3,
      created_at: "2026-01-31T10:00:00Z",
      scheduled_at: nil,
      dispatched_at: "2026-01-31T10:00:01Z",
      completed_at: "2026-01-31T10:00:02Z",
      last_error: nil,
      last_response_status: 200
    }
  })
end
