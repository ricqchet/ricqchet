defmodule RicqchetWeb.Schemas.Auth.LoginResponse do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "LoginResponse",
    description: "Response after successful login",
    type: :object,
    properties: %{
      user: %Schema{
        type: :object,
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          email: %Schema{type: :string, format: :email},
          role: %Schema{type: :string},
          status: %Schema{type: :string},
          tenant_id: %Schema{type: :string, format: :uuid},
          tenant_name: %Schema{type: :string}
        }
      },
      access_token: %Schema{
        type: :string,
        description: "JWT access token for authentication"
      },
      refresh_token: %Schema{
        type: :string,
        description: "Refresh token for obtaining new access tokens"
      },
      expires_in: %Schema{
        type: :integer,
        description: "Access token expiration time in seconds"
      }
    },
    required: [:user, :access_token, :refresh_token, :expires_in],
    example: %{
      "user" => %{
        "id" => "123e4567-e89b-12d3-a456-426614174000",
        "email" => "user@example.com",
        "role" => "admin",
        "status" => "active",
        "tenant_id" => "123e4567-e89b-12d3-a456-426614174001",
        "tenant_name" => "Acme Corp"
      },
      "access_token" => "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      "refresh_token" => "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4...",
      "expires_in" => 900
    }
  })
end
