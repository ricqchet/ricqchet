defmodule RicqchetWeb.ChannelNamespaceController do
  @moduledoc """
  Controller for channel namespace configuration.

  Namespaces define pattern-based configuration for channels within an application.
  They control features like history, authentication, and member limits.

  ## Authorization

  - **List**: Any authenticated tenant member
  - **Create/Update/Delete**: Tenant admin only
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.Applications
  alias Ricqchet.Channels.NamespaceConfig
  alias Ricqchet.Channels.Namespaces
  alias Ricqchet.Users.User
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["channel-namespaces"])

  operation(:index,
    summary: "List channel namespaces",
    description: "Returns all channel namespace configurations for an application.",
    parameters: [
      application_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Application ID"
      ]
    ],
    responses:
      Schemas.Helpers.list_responses(
        Schemas.Channels.NamespaceList,
        [401, 404, 429]
      ),
    security: [%{"bearer_auth" => []}]
  )

  def index(conn, %{"application_id" => app_id}) do
    tenant = conn.assigns.current_tenant

    with {:ok, application} <- get_application_or_error(tenant, app_id) do
      namespaces = Namespaces.list_namespaces(application.id)
      render(conn, :index, namespaces: namespaces)
    end
  end

  operation(:create,
    summary: "Create a channel namespace",
    description: "Creates a new channel namespace configuration. Admin only.",
    parameters: [
      application_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Application ID"
      ]
    ],
    request_body:
      {"Namespace configuration", "application/json", Schemas.Channels.NamespaceParams},
    responses:
      Schemas.Helpers.create_responses(
        Schemas.Channels.NamespaceResponse,
        201,
        [401, 403, 404, 422, 429]
      ),
    security: [%{"bearer_auth" => []}]
  )

  def create(conn, %{"application_id" => app_id} = params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, application} <- get_application_or_error(tenant, app_id),
         namespace_params = Map.drop(params, ["application_id"]),
         {:ok, namespace} <-
           Namespaces.create_namespace(namespace_params, application.id, tenant.id) do
      NamespaceConfig.invalidate_cache(application.id)

      conn
      |> put_status(:created)
      |> render(:show, namespace: namespace)
    end
  end

  operation(:update,
    summary: "Update a channel namespace",
    description: "Updates an existing channel namespace configuration. Admin only.",
    parameters: [
      application_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Application ID"
      ],
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Namespace ID"
      ]
    ],
    request_body:
      {"Namespace configuration", "application/json", Schemas.Channels.NamespaceParams},
    responses:
      Schemas.Helpers.update_responses(
        Schemas.Channels.NamespaceResponse,
        [401, 403, 404, 422, 429]
      ),
    security: [%{"bearer_auth" => []}]
  )

  def update(conn, %{"application_id" => app_id, "id" => id} = params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, application} <- get_application_or_error(tenant, app_id),
         {:ok, namespace} <- get_namespace_or_error(id, application.id),
         {:ok, updated} <-
           Namespaces.update_namespace(namespace, Map.drop(params, ["application_id", "id"])) do
      NamespaceConfig.invalidate_cache(application.id)
      render(conn, :show, namespace: updated)
    end
  end

  operation(:delete,
    summary: "Delete a channel namespace",
    description: "Deletes a channel namespace configuration. Admin only.",
    parameters: [
      application_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Application ID"
      ],
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Namespace ID"
      ]
    ],
    responses:
      Map.merge(%{204 => "No Content"}, Schemas.Helpers.error_responses([401, 403, 404, 429])),
    security: [%{"bearer_auth" => []}]
  )

  def delete(conn, %{"application_id" => app_id, "id" => id}) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, application} <- get_application_or_error(tenant, app_id),
         {:ok, namespace} <- get_namespace_or_error(id, application.id),
         {:ok, _deleted} <- Namespaces.delete_namespace(namespace) do
      NamespaceConfig.invalidate_cache(application.id)
      send_resp(conn, :no_content, "")
    end
  end

  defp authorize_admin(%User{role: "admin"}), do: :ok
  defp authorize_admin(_user), do: {:error, :forbidden}

  defp get_application_or_error(tenant, app_id) do
    case Applications.get_application_by_tenant(tenant, app_id) do
      nil -> {:error, :not_found}
      application -> {:ok, application}
    end
  end

  defp get_namespace_or_error(id, application_id) do
    case Namespaces.get_namespace(id, application_id) do
      nil -> {:error, :not_found}
      namespace -> {:ok, namespace}
    end
  end
end
