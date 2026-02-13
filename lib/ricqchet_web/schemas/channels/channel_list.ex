defmodule RicqchetWeb.Schemas.Channels.ChannelList do
  @moduledoc """
  Schema for listing active channels.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ChannelList",
    description: "List of active channels with summary information",
    type: :object,
    required: [:channels],
    properties: %{
      channels: %Schema{
        type: :array,
        description: "List of active channels",
        items: %Schema{
          type: :object,
          required: [:name, :subscriber_count, :type],
          properties: %{
            name: %Schema{
              type: :string,
              description: "Channel name"
            },
            subscriber_count: %Schema{
              type: :integer,
              minimum: 0,
              description: "Number of active subscribers on the channel"
            },
            type: %Schema{
              type: :string,
              enum: ["public", "private", "presence"],
              description: "Channel type determined by the name prefix"
            }
          }
        }
      }
    },
    example: %{
      channels: [
        %{name: "public-chat", subscriber_count: 12, type: "public"},
        %{name: "private-updates", subscriber_count: 5, type: "private"},
        %{name: "presence-lobby", subscriber_count: 3, type: "presence"}
      ]
    }
  })
end
