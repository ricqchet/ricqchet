defmodule RicqchetWeb.ApplicationController do
  @moduledoc """
  Controller for application management.

  Applications represent software/services within a tenant that can use the Ricqchet API.
  Each application can have multiple API keys for authentication.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.ApiKeys
  alias Ricqchet.Applications
  alias Ricqchet.Repo
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["applications"])

  operation(:index,
    summary: "List applications",
    description: "Returns a paginated list of all applications in the current tenant.",
    responses: Schemas.Helpers.list_responses(Schemas.ApplicationList),
    security: [%{"bearer_auth" => []}]
  )

  operation(:show,
    summary: "Get application details",
    description:
      "Retrieves detailed information about an application, including its API keys (with secrets redacted).",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Application ID"
      ]
    ],
    responses: Schemas.Helpers.show_responses(Schemas.ApplicationDetail),
    security: [%{"bearer_auth" => []}]
  )

  operation(:create,
    summary: "Create application",
    description: """
    Creates a new application within the current tenant.

    A default API key is automatically created and returned in the response.
    **Important:** Store the API key securely - it will not be shown again.
    """,
    request_body:
      {"Application parameters", "application/json", Schemas.ApplicationRequest, required: true},
    responses: Schemas.Helpers.create_responses(Schemas.ApplicationCreatedResponse, 201),
    security: [%{"bearer_auth" => []}]
  )

  operation(:update,
    summary: "Update application",
    description:
      "Updates an existing application's name, description, status, or DLQ destination.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Application ID"
      ]
    ],
    request_body:
      {"Application parameters", "application/json", Schemas.ApplicationUpdateRequest,
       required: true},
    responses: Schemas.Helpers.update_responses(Schemas.ApplicationDetail),
    security: [%{"bearer_auth" => []}]
  )

  operation(:delete,
    summary: "Delete application",
    description: """
    Deletes an application and revokes all associated API keys.

    **Warning:** This action is irreversible. All API keys will be immediately revoked
    and any requests using those keys will fail.
    """,
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Application ID"
      ]
    ],
    responses: Schemas.Helpers.delete_responses(Schemas.ApplicationDeletedResponse),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Lists all applications for the current tenant.
  """
  def index(conn, _params) do
    tenant = conn.assigns.current_tenant

    applications =
      tenant
      |> Applications.list_applications_for_tenant()
      |> Repo.preload(:api_keys)

    render(conn, :index, applications: applications, total: length(applications))
  end

  @doc """
  Gets a single application with its API keys.
  """
  def show(conn, %{"id" => id}) do
    tenant = conn.assigns.current_tenant

    case Applications.get_application_by_tenant(tenant, id) do
      nil ->
        {:error, :not_found}

      application ->
        application = Repo.preload(application, :api_keys)
        render(conn, :show, application: application)
    end
  end

  @doc """
  Creates a new application with an initial API key.
  """
  def create(conn, params) do
    tenant = conn.assigns.current_tenant

    result =
      Repo.transaction(fn ->
        with {:ok, application} <- Applications.create_application(tenant, params),
             {:ok, api_key} <- ApiKeys.create_api_key(application, %{name: "Default"}) do
          {application, api_key}
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, {application, api_key}} ->
        conn
        |> put_status(:created)
        |> render(:created, application: application, api_key: api_key)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates an existing application.
  """
  def update(conn, %{"id" => id} = params) do
    tenant = conn.assigns.current_tenant

    case Applications.get_application_by_tenant(tenant, id) do
      nil ->
        {:error, :not_found}

      application ->
        update_params = Map.drop(params, ["id"])

        case Applications.update_application(application, update_params) do
          {:ok, updated_application} ->
            updated_application = Repo.preload(updated_application, :api_keys)
            render(conn, :updated, application: updated_application)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Deletes an application and revokes all its API keys.
  """
  def delete(conn, %{"id" => id}) do
    tenant = conn.assigns.current_tenant

    case Applications.get_application_by_tenant(tenant, id) do
      nil ->
        {:error, :not_found}

      application ->
        application = Repo.preload(application, :api_keys)
        api_key_count = length(application.api_keys)

        case delete_application_with_keys(application) do
          {:ok, :ok} ->
            render(conn, :deleted, id: id, api_keys_revoked: api_key_count)

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp delete_application_with_keys(application) do
    Repo.transaction(fn ->
      with :ok <- revoke_all_api_keys(application.api_keys),
           {:ok, _} <- Applications.delete_application(application) do
        :ok
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp revoke_all_api_keys(api_keys) do
    Enum.reduce_while(api_keys, :ok, fn api_key, _acc ->
      case ApiKeys.revoke_api_key(api_key) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
