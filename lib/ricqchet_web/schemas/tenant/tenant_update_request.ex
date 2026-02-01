defmodule RicqchetWeb.Schemas.Tenant.TenantUpdateRequest do
  @moduledoc """
  Schema for tenant update request.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "TenantUpdateRequest",
    description: "Parameters for updating a tenant",
    type: :object,
    properties: %{
      name: %Schema{
        type: :string,
        description: "Tenant name",
        minLength: 1,
        maxLength: 255
      },
      default_max_retries: %Schema{
        type: :integer,
        description: "Default maximum retry attempts for message delivery",
        minimum: 0,
        maximum: 10
      }
    },
    example: %{
      "name" => "Updated Acme Corp",
      "default_max_retries" => 5
    }
  })
end
