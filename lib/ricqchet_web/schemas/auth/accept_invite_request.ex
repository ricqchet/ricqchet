defmodule RicqchetWeb.Schemas.Auth.AcceptInviteRequest do
  @moduledoc """
  Schema for accept invite request.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "AcceptInviteRequest",
    description: "Parameters for accepting a tenant invitation",
    type: :object,
    required: [:token, :password],
    properties: %{
      token: %Schema{
        type: :string,
        description: "Invitation token received in the invitation email"
      },
      password: %Schema{
        type: :string,
        format: :password,
        description: "Password for the new account (12-72 characters)",
        minLength: 12,
        maxLength: 72
      }
    },
    example: %{
      "token" => "abc123...",
      "password" => "secure_password_123"
    }
  })
end
