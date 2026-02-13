defmodule RicqchetWeb.Schemas.Channels.NamespaceResponse do
  @moduledoc """
  Schema for a single namespace response wrapped in a data key.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "NamespaceResponse",
    description: "Response containing a single channel namespace configuration",
    type: :object,
    required: [:data],
    properties: %{
      data: %Schema{
        type: :object,
        required: [:id, :pattern, :inserted_at, :updated_at],
        description: "Namespace configuration",
        properties: %{
          id: %Schema{
            type: :string,
            format: :uuid,
            description: "Unique namespace identifier"
          },
          pattern: %Schema{
            type: :string,
            description: "Glob pattern to match channel names"
          },
          priority: %Schema{
            type: :integer,
            description: "Priority for pattern matching"
          },
          history_enabled: %Schema{
            type: :boolean,
            description: "Whether event history is enabled"
          },
          history_ttl_seconds: %Schema{
            type: :integer,
            nullable: true,
            description: "Time-to-live in seconds for historical events"
          },
          history_max_events: %Schema{
            type: :integer,
            nullable: true,
            description: "Maximum number of events to retain per channel"
          },
          cache_enabled: %Schema{
            type: :boolean,
            description: "Whether cache channels are enabled"
          },
          max_members: %Schema{
            type: :integer,
            nullable: true,
            description: "Maximum number of members for presence channels"
          },
          max_event_size_bytes: %Schema{
            type: :integer,
            nullable: true,
            description: "Maximum event payload size in bytes"
          },
          max_client_events_per_second: %Schema{
            type: :integer,
            nullable: true,
            description: "Rate limit for client-triggered events per second"
          },
          auth_endpoint: %Schema{
            type: :string,
            nullable: true,
            description: "Custom authentication endpoint URL"
          },
          webhook_url: %Schema{
            type: :string,
            nullable: true,
            description: "Webhook URL for channel lifecycle events"
          },
          inserted_at: %Schema{
            type: :string,
            format: :"date-time",
            description: "Timestamp when the namespace was created"
          },
          updated_at: %Schema{
            type: :string,
            format: :"date-time",
            description: "Timestamp when the namespace was last updated"
          }
        }
      }
    },
    example: %{
      data: %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        pattern: "private-chat-*",
        priority: 10,
        history_enabled: true,
        history_ttl_seconds: 86_400,
        history_max_events: 1000,
        cache_enabled: false,
        max_members: 100,
        max_event_size_bytes: 10_240,
        max_client_events_per_second: 10,
        auth_endpoint: "https://example.com/auth/channel",
        webhook_url: "https://example.com/webhooks/channels",
        inserted_at: "2026-01-15T10:00:00Z",
        updated_at: "2026-01-20T14:30:00Z"
      }
    }
  })
end
