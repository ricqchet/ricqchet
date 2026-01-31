defmodule RicqchetWeb.TenantController do
  @moduledoc """
  Controller for tenant-specific information.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["tenant"])

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
