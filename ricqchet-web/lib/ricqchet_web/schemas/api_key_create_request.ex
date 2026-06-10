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
      },
      scope: %Schema{
        type: :string,
        enum: ["relay", "subscribe"],
        default: "relay",
        description:
          "Permission scope. Defaults to `relay` (full server-side key). Use " <>
            "`subscribe` to mint a browser-safe key that can only subscribe to " <>
            "channels over the WebSocket and is rejected on every REST endpoint."
      }
    },
    example: %{
      name: "Production Key",
      expires_at: "2027-01-15T10:00:00Z",
      scope: "relay"
    }
  })
end
