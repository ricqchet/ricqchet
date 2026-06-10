defmodule RicqchetWeb.Schemas.Channels.ChannelInfo do
  @moduledoc """
  Schema for detailed channel information.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ChannelInfo",
    description: "Detailed information about a specific channel",
    type: :object,
    required: [:name, :type, :subscriber_count, :occupied],
    properties: %{
      name: %Schema{
        type: :string,
        description: "Channel name"
      },
      type: %Schema{
        type: :string,
        enum: ["public", "private", "presence"],
        description: "Channel type determined by the name prefix"
      },
      subscriber_count: %Schema{
        type: :integer,
        minimum: 0,
        description: "Number of active subscribers on the channel"
      },
      occupied: %Schema{
        type: :boolean,
        description: "Whether the channel has any active subscribers"
      },
      members: %Schema{
        type: :array,
        nullable: true,
        description:
          "List of members on a presence channel. Only included for presence channels.",
        items: %Schema{
          type: :object,
          required: [:user_id],
          properties: %{
            user_id: %Schema{
              type: :string,
              description: "Unique user identifier"
            },
            user_info: %Schema{
              type: :object,
              description: "Arbitrary user metadata provided during authentication",
              additionalProperties: true
            }
          }
        }
      }
    },
    example: %{
      name: "presence-lobby",
      type: "presence",
      subscriber_count: 3,
      occupied: true,
      members: [
        %{user_id: "user_1", user_info: %{name: "Alice"}},
        %{user_id: "user_2", user_info: %{name: "Bob"}}
      ]
    }
  })
end
