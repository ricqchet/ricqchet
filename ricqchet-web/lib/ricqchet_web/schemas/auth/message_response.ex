defmodule RicqchetWeb.Schemas.Auth.MessageResponse do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MessageResponse",
    description: "A simple response with a message",
    type: :object,
    properties: %{
      message: %Schema{
        type: :string,
        description: "Response message"
      }
    },
    required: [:message],
    example: %{
      "message" => "Operation completed successfully"
    }
  })
end
