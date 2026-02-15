defmodule RicqchetWeb.Schemas.MessageList do
  @moduledoc """
  Schema for message list response.
  """

  use RicqchetWeb.Schema

  alias RicqchetWeb.Schemas.Message

  OpenApiSpex.schema(%{
    title: "MessageList",
    description: "List of messages",
    type: :object,
    required: [:messages, :has_more],
    properties: %{
      messages: %Schema{
        type: :array,
        items: Message,
        description: "List of messages"
      },
      has_more: %Schema{
        type: :boolean,
        description: "Whether more messages are available"
      }
    },
    example: %{
      messages: [
        %{
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
      ],
      has_more: false
    }
  })
end
