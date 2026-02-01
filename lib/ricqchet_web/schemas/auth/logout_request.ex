defmodule RicqchetWeb.Schemas.Auth.LogoutRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "LogoutRequest",
    description: "Request body for user logout",
    type: :object,
    properties: %{
      refresh_token: %Schema{
        type: :string,
        description: "The refresh token to revoke"
      },
      everywhere: %Schema{
        type: :boolean,
        description: "If true, invalidates all sessions for the user",
        default: false
      }
    },
    required: [:refresh_token],
    example: %{
      "refresh_token" => "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4...",
      "everywhere" => false
    }
  })
end
