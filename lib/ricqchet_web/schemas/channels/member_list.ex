defmodule RicqchetWeb.Schemas.Channels.MemberList do
  @moduledoc """
  Schema for listing members of a presence channel.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "MemberList",
    description: "List of members currently subscribed to a presence channel",
    type: :object,
    required: [:members],
    properties: %{
      members: %Schema{
        type: :array,
        description: "List of channel members",
        items: %Schema{
          type: :object,
          required: [:user_id, :joined_at],
          properties: %{
            user_id: %Schema{
              type: :string,
              description: "Unique user identifier"
            },
            user_info: %Schema{
              type: :object,
              nullable: true,
              description: "Arbitrary user metadata provided during authentication",
              additionalProperties: true
            },
            joined_at: %Schema{
              type: :string,
              format: :"date-time",
              description: "Timestamp when the member joined the channel"
            }
          }
        }
      }
    },
    example: %{
      members: [
        %{
          user_id: "user_1",
          user_info: %{name: "Alice", avatar: "https://example.com/alice.png"},
          joined_at: "2026-01-15T10:00:00Z"
        },
        %{
          user_id: "user_2",
          user_info: %{name: "Bob"},
          joined_at: "2026-01-15T10:05:00Z"
        }
      ]
    }
  })
end
