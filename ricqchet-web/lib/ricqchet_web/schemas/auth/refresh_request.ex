defmodule RicqchetWeb.Schemas.Auth.RefreshRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "RefreshRequest",
    description: "Request body for refreshing access token",
    type: :object,
    properties: %{
      refresh_token: %Schema{
        type: :string,
        description: "The refresh token obtained during login"
      }
    },
    required: [:refresh_token],
    example: %{
      "refresh_token" => "dGhpcyBpcyBhIHJlZnJlc2ggdG9rZW4..."
    }
  })
end
