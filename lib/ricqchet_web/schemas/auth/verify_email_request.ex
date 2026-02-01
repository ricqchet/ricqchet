defmodule RicqchetWeb.Schemas.Auth.VerifyEmailRequest do
  @moduledoc false

  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "VerifyEmailRequest",
    description: "Request body for email verification",
    type: :object,
    properties: %{
      token: %Schema{
        type: :string,
        description: "The verification token sent to the user's email"
      }
    },
    required: [:token],
    example: %{
      "token" => "abc123verification"
    }
  })
end
