defmodule RicqchetWeb.Schemas.Channels.NamespaceParams do
  @moduledoc """
  Schema for creating or updating a channel namespace.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "NamespaceParams",
    description: "Request body for creating or updating a channel namespace configuration",
    type: :object,
    required: [:pattern],
    properties: %{
      pattern: %Schema{
        type: :string,
        minLength: 1,
        maxLength: 255,
        description: "Glob pattern to match channel names (e.g., `public-*`, `private-chat-*`)"
      },
      priority: %Schema{
        type: :integer,
        minimum: 0,
        default: 0,
        description:
          "Priority for pattern matching when multiple namespaces match. Higher values take precedence."
      },
      history_enabled: %Schema{
        type: :boolean,
        default: false,
        description: "Whether to persist event history for matching channels"
      },
      history_ttl_seconds: %Schema{
        type: :integer,
        minimum: 0,
        nullable: true,
        description: "Time-to-live in seconds for historical events. Null for no expiration."
      },
      history_max_events: %Schema{
        type: :integer,
        minimum: 1,
        nullable: true,
        description: "Maximum number of events to retain per channel. Null for no limit."
      },
      cache_enabled: %Schema{
        type: :boolean,
        default: false,
        description: "Whether to enable cache channels for matching channel names"
      },
      max_members: %Schema{
        type: :integer,
        minimum: 1,
        nullable: true,
        description:
          "Maximum number of members allowed on matching presence channels. Null for no limit."
      },
      max_event_size_bytes: %Schema{
        type: :integer,
        minimum: 1,
        nullable: true,
        description: "Maximum event payload size in bytes. Null to use the application default."
      },
      max_client_events_per_second: %Schema{
        type: :integer,
        minimum: 1,
        nullable: true,
        description:
          "Rate limit for client-triggered events per second per connection. Null for no limit."
      },
      auth_endpoint: %Schema{
        type: :string,
        format: :uri,
        nullable: true,
        description: "Custom authentication endpoint URL for private and presence channels"
      },
      webhook_url: %Schema{
        type: :string,
        format: :uri,
        nullable: true,
        description:
          "Webhook URL for channel lifecycle events (e.g., channel_occupied, member_added)"
      }
    },
    example: %{
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
      webhook_url: "https://example.com/webhooks/channels"
    }
  })
end
