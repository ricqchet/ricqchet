defmodule RicqchetWeb.Schemas.ApiKeyCreateRequest do
  @moduledoc """
  Schema for create API key request.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "ApiKeyCreateRequest",
    description: "Request body for creating a new API key",
    type: :object,
    required: [:name],
    properties: %{
      name: %Schema{
        type: :string,
        minLength: 1,
        maxLength: 255,
        description: "Human-readable name for the API key"
      },
      expires_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Optional expiration timestamp for the key"
      }
    },
    example: %{
      name: "Production Key",
      expires_at: "2027-01-15T10:00:00Z"
    }
  })
end
