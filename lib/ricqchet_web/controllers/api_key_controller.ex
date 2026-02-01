defmodule RicqchetWeb.ApiKeyController do
  @moduledoc """
  Controller for API key management.

  API keys are used to authenticate requests to the Ricqchet API.
  Each key belongs to an application within a tenant.

  ## Authorization

  - **List/Create**: Any authenticated tenant member (admin, member, or viewer can list; admin only for create)
  - **Revoke/Rotate**: Tenant admin only

  ## Security

  - Full API key is only returned on creation and rotation
  - List and show endpoints only return the key prefix
  - Keys are hashed using Argon2 before storage
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.ApiKeys
  alias Ricqchet.Applications
  alias Ricqchet.Users.User
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["api-keys"])

  operation(:index,
    summary: "List API keys",
    description: """
    Returns a list of all API keys for an application.

    **Security:** Only the key prefix is returned, not the full API key.
    """,
    parameters: [
      application_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Application ID"
      ]
    ],
    responses: Schemas.Helpers.list_responses(Schemas.ApiKeyList),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Lists all API keys for an application.
  """
  def index(conn, %{"application_id" => application_id}) do
    tenant = conn.assigns.current_tenant

    case Applications.get_application_by_tenant(tenant, application_id) do
      nil ->
        {:error, :not_found}

      application ->
        api_keys = ApiKeys.list_api_keys_for_application(application)
        render(conn, :index, api_keys: api_keys, total: length(api_keys))
    end
  end

  operation(:create,
    summary: "Create API key",
    description: """
    Creates a new API key for an application.

    **Requires admin role.**

    **Important:** The full API key is only returned in this response.
    Store it securely - it will not be shown again.
    """,
    parameters: [
      application_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Application ID"
      ]
    ],
    request_body:
      {"API key parameters", "application/json", Schemas.ApiKeyCreateRequest, required: true},
    responses:
      Schemas.Helpers.create_responses(Schemas.ApiKeyCreatedResponse, 201, [
        401,
        403,
        404,
        422,
        429
      ]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Creates a new API key for an application.

  Requires admin role.
  """
  def create(conn, %{"application_id" => application_id} = params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, application} <- get_application_or_error(tenant, application_id),
         {:ok, api_key} <- ApiKeys.create_api_key(application, params) do
      conn
      |> put_status(:created)
      |> render(:created, api_key: api_key)
    end
  end

  operation(:delete,
    summary: "Revoke API key",
    description: """
    Revokes an API key immediately.

    **Requires admin role.**

    **Warning:** This action cannot be undone. Any requests using this key
    will immediately fail authentication.
    """,
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "API Key ID"
      ]
    ],
    responses:
      Schemas.Helpers.delete_responses(Schemas.ApiKeyRevokedResponse, [401, 403, 404, 429]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Revokes an API key.

  Requires admin role.
  """
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, api_key} <- get_api_key_or_error(tenant, id),
         {:ok, revoked_key} <- ApiKeys.revoke_api_key(api_key) do
      render(conn, :revoked, api_key: revoked_key)
    end
  end

  operation(:rotate,
    summary: "Rotate API key",
    description: """
    Rotates an API key by revoking the old key and creating a new one atomically.

    **Requires admin role.**

    **Important:** The full new API key is only returned in this response.
    Store it securely - it will not be shown again.

    The old key is immediately revoked and can no longer be used.
    """,
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "API Key ID to rotate"
      ]
    ],
    responses:
      Schemas.Helpers.create_responses(Schemas.ApiKeyRotatedResponse, 200, [
        401,
        403,
        404,
        422,
        429
      ]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Rotates an API key (revokes old, creates new).

  Requires admin role.
  """
  def rotate(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, api_key} <- get_api_key_or_error(tenant, id),
         {:ok, {revoked_key, new_api_key}} <- ApiKeys.rotate_api_key(api_key) do
      render(conn, :rotated, old_api_key: revoked_key, new_api_key: new_api_key)
    end
  end

  # Authorization helpers

  defp authorize_admin(%User{role: "admin"}), do: :ok
  defp authorize_admin(_user), do: {:error, :forbidden}

  # Resource helpers

  defp get_application_or_error(tenant, id) do
    case Applications.get_application_by_tenant(tenant, id) do
      nil -> {:error, :not_found}
      application -> {:ok, application}
    end
  end

  defp get_api_key_or_error(tenant, id) do
    case ApiKeys.get_api_key_with_application(id) do
      nil ->
        {:error, :not_found}

      %{application: %{tenant_id: tenant_id}} = api_key when tenant_id == tenant.id ->
        {:ok, api_key}

      _api_key ->
        # API key exists but belongs to different tenant - return not_found for security
        {:error, :not_found}
    end
  end
end
