defmodule RicqchetWeb.Schemas.ApplicationDeletedResponse do
  @moduledoc """
  Schema for application deletion response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApplicationDeletedResponse",
    description: "Response after deleting an application",
    type: :object,
    required: [:deleted, :id],
    properties: %{
      deleted: %Schema{
        type: :boolean,
        description: "Indicates the application was successfully deleted"
      },
      id: %Schema{
        type: :string,
        format: :uuid,
        description: "ID of the deleted application"
      },
      api_keys_revoked: %Schema{
        type: :integer,
        minimum: 0,
        description: "Number of API keys that were revoked"
      }
    },
    example: %{
      deleted: true,
      id: "550e8400-e29b-41d4-a716-446655440000",
      api_keys_revoked: 2
    }
  })
end
