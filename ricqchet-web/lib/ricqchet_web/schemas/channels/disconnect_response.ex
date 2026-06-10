defmodule RicqchetWeb.Schemas.Channels.DisconnectResponse do
  @moduledoc """
  Schema for the response after disconnecting a user's connections.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "DisconnectResponse",
    description: "Response after successfully disconnecting all connections for a user",
    type: :object,
    required: [:status, :user_id],
    properties: %{
      status: %Schema{
        type: :string,
        enum: ["ok"],
        description: "Operation status"
      },
      user_id: %Schema{
        type: :string,
        description: "The user ID whose connections were terminated"
      }
    },
    example: %{
      status: "ok",
      user_id: "user_1"
    }
  })
end
