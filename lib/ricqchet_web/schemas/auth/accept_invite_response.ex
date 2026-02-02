defmodule RicqchetWeb.Schemas.Auth.AcceptInviteResponse do
  @moduledoc """
  Schema for accept invite response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "AcceptInviteResponse",
    description: "Response after successfully accepting an invitation",
    type: :object,
    required: [:user, :access_token, :refresh_token, :expires_in],
    properties: %{
      user: %Schema{
        type: :object,
        required: [:id, :email, :role, :status, :tenant_id, :tenant_name],
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          email: %Schema{type: :string, format: :email},
          role: %Schema{type: :string, enum: ["admin", "member", "viewer"]},
          status: %Schema{type: :string, enum: ["active", "pending", "suspended"]},
          tenant_id: %Schema{type: :string, format: :uuid},
          tenant_name: %Schema{type: :string}
        }
      },
      access_token: %Schema{
        type: :string,
        description: "JWT access token for API requests"
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
    example: %{
      user: %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        email: "user@example.com",
        role: "member",
        status: "active",
        tenant_id: "660e8400-e29b-41d4-a716-446655440000",
        tenant_name: "Acme Corp"
      },
      access_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
      refresh_token: "rt_abc123...",
      expires_in: 900
    }
  })
end
