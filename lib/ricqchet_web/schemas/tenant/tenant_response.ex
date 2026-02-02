defmodule RicqchetWeb.Schemas.Tenant.TenantResponse do
  @moduledoc """
  Schema for tenant response.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "TenantResponse",
    description: "Tenant information. Admins see additional sensitive fields.",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Tenant ID"},
      name: %Schema{type: :string, description: "Tenant name"},
      status: %Schema{
        type: :string,
        description: "Tenant status",
        enum: ["active", "suspended"]
      },
      default_max_retries: %Schema{
        type: :integer,
        description: "Default maximum retry attempts for message delivery",
        minimum: 0,
        maximum: 10
      },
      signing_secret: %Schema{
        type: :string,
        description: "Base64-encoded signing secret for webhook verification (admin only)",
        nullable: true
      },
      inserted_at: %Schema{
        type: :string,
        format: "date-time",
        description: "Tenant creation timestamp"
      },
      updated_at: %Schema{
        type: :string,
        format: "date-time",
        description: "Last update timestamp"
      }
    },
    required: [:id, :name, :status, :default_max_retries, :inserted_at, :updated_at],
    example: %{
      "id" => "123e4567-e89b-12d3-a456-426614174000",
      "name" => "Acme Corp",
      "status" => "active",
      "default_max_retries" => 3,
      "signing_secret" => "YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=",
      "inserted_at" => "2024-01-10T08:00:00Z",
      "updated_at" => "2024-01-20T14:00:00Z"
    }
  })
end
