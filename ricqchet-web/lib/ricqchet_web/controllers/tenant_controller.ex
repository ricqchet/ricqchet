defmodule RicqchetWeb.TenantController do
  @moduledoc """
  Controller for tenant management.

  Provides endpoints for viewing and updating tenant information.

  ## Authorization

  - **Show**: Any authenticated tenant member can view basic info, admins see sensitive fields
  - **Update**: Tenant admin only
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.Authorization
  alias Ricqchet.Tenants
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["tenant"])

  operation(:show,
    summary: "Get current tenant",
    description: """
    Returns details about the current tenant.

    All authenticated users can view basic tenant information.
    Admins see additional sensitive fields like the signing secret.
    """,
    responses: Schemas.Helpers.show_responses(Schemas.Tenant.TenantResponse, [401, 429]),
    security: [%{"bearerAuth" => []}]
  )

  @doc """
  Returns the current tenant's details.

  Admins see additional sensitive fields like signing_secret.
  """
  def show(conn, _params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    render(conn, :show, tenant: tenant, is_admin: Authorization.admin?(user))
  end

  operation(:update,
    summary: "Update current tenant",
    description: """
    Updates the current tenant's name or default settings.

    **Requires admin role.**
    """,
    request_body:
      {"Tenant parameters", "application/json", Schemas.Tenant.TenantUpdateRequest,
       required: true},
    responses:
      Schemas.Helpers.update_responses(Schemas.Tenant.TenantResponse, [401, 403, 422, 429]),
    security: [%{"bearerAuth" => []}]
  )

  @doc """
  Updates the current tenant.

  Requires admin role.
  """
  def update(conn, params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- Authorization.authorize(user, :admin),
         {:ok, updated_tenant} <- Tenants.update_tenant(tenant, params) do
      render(conn, :show, tenant: updated_tenant, is_admin: true)
    end
  end

  operation(:signing_secret,
    summary: "Get signing secret",
    description: """
    Returns the signing secret for your tenant.

    Use this secret to verify incoming webhook deliveries from Ricqchet.
    The signature is included in the `X-Ricqchet-Signature` header.

    ## Verification

    1. Parse the header: `X-Ricqchet-Signature: t=<timestamp>,v1=<signature>`
    2. Compute: `HMAC-SHA256(signing_secret, "<timestamp>.<raw_body>")`
    3. Compare the computed signature with `v1` (use constant-time comparison)
    4. Optionally reject if timestamp is too old (e.g., > 5 minutes)
    """,
    responses:
      Map.merge(
        %{
          200 =>
            Schemas.Helpers.json_response(
              %Schema{
                type: :object,
                properties: %{
                  signing_secret: %Schema{
                    type: :string,
                    description: "Base64-encoded signing secret"
                  }
                },
                required: [:signing_secret]
              },
              "Success"
            )
        },
        Schemas.Helpers.error_responses([401, 429])
      ),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Returns the tenant's signing secret for webhook verification.
  """
  def signing_secret(conn, _params) do
    tenant = conn.assigns.current_tenant

    render(conn, :signing_secret, signing_secret: tenant.signing_secret)
  end
end
