defmodule RicqchetWeb.Schemas.Auth.RefreshResponse do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "RefreshResponse",
    description: "Response after successful token refresh",
    type: :object,
    properties: %{
      access_token: %Schema{
        type: :string,
        description: "New JWT access token"
      },
      expires_in: %Schema{
        type: :integer,
        description: "Access token expiration time in seconds"
      }
    },
    required: [:access_token, :expires_in],
    example: %{
      "access_token" => "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      "expires_in" => 900
    }
  })
end
