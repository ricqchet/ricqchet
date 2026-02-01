defmodule RicqchetWeb.ApplicationController do
  @moduledoc """
  Controller for application management.

  Applications represent software/services within a tenant that can use the Ricqchet API.
  Each application can have multiple API keys for authentication.

  ## Authorization

  - **List/Show**: Any authenticated tenant member (admin, member, or viewer)
  - **Create/Update/Delete**: Tenant admin only
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.ApiKeys
  alias Ricqchet.Applications
  alias Ricqchet.Repo
  alias Ricqchet.Users.User
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["applications"])

  operation(:index,
    summary: "List applications",
    description: """
    Returns a paginated list of applications in the current tenant.

    Supports cursor-based pagination (recommended for large datasets):
    - `first` + optional `after` cursor for forward pagination
    - `last` + optional `before` cursor for backward pagination

    Or offset-based pagination:
    - `offset` + `limit`

    **Filtering:**
    - `filters[0][field]=name&filters[0][op]=ilike&filters[0][value]=prod`
    - `filters[0][field]=status&filters[0][value]=active`

    **Sorting:**
    - `order_by[]=name&order_directions[]=asc`

    Requires JWT authentication.
    """,
    parameters: [
      first: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100},
        description: "Number of items to return (forward pagination)"
      ],
      after: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Cursor for forward pagination (from previous response)"
      ],
      last: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100},
        description: "Number of items to return (backward pagination)"
      ],
      before: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Cursor for backward pagination (from previous response)"
      ],
      offset: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 0},
        description: "Offset for offset-based pagination"
      ],
      limit: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100},
        description: "Number of items to return (offset pagination)"
      ],
      order_by: [
        in: :query,
        schema: %Schema{
          type: :array,
          items: %Schema{type: :string, enum: ~w(name status inserted_at updated_at)}
        },
        description: "Fields to sort by"
      ],
      order_directions: [
        in: :query,
        schema: %Schema{type: :array, items: %Schema{type: :string, enum: ~w(asc desc)}},
        description: "Sort directions for each order_by field"
      ]
    ],
    responses: Schemas.Helpers.list_responses(Schemas.ApplicationList, [401, 422, 429]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Lists applications for the current tenant with pagination.
  """
  def index(conn, params) do
    tenant = conn.assigns.current_tenant
    flop_params = extract_flop_params(params)

    case Applications.list_applications_for_tenant(tenant, flop_params) do
      {:ok, {applications, meta}} ->
        applications = Repo.preload(applications, :api_keys)
        render(conn, :index, applications: applications, meta: meta)

      {:error, meta} ->
        {:error, :validation, flop_errors_to_map(meta)}
    end
  end

  operation(:show,
    summary: "Get application details",
    description: """
    Retrieves detailed information about an application, including its API keys (with secrets redacted).
    Requires JWT authentication.
    """,
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

  operation(:create,
    summary: "Create application",
    description: """
    Creates a new application within the current tenant.

    **Requires admin role.**

    A default API key is automatically created and returned in the response.
    **Important:** Store the API key securely - it will not be shown again.
    """,
    request_body:
      {"Application parameters", "application/json", Schemas.ApplicationRequest, required: true},
    responses:
      Schemas.Helpers.create_responses(Schemas.ApplicationCreatedResponse, 201, [
        401,
        403,
        422,
        429
      ]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Creates a new application with an initial API key.

  Requires admin role.
  """
  def create(conn, params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, {application, api_key}} <- create_application_with_key(tenant, params) do
      conn
      |> put_status(:created)
      |> render(:created, application: application, api_key: api_key)
    end
  end

  operation(:update,
    summary: "Update application",
    description: """
    Updates an existing application's name, description, status, or DLQ destination.

    **Requires admin role.**
    """,
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
    responses:
      Schemas.Helpers.update_responses(Schemas.ApplicationDetail, [401, 403, 404, 422, 429]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Updates an existing application.

  Requires admin role.
  """
  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant
    update_params = Map.drop(params, ["id"])

    with :ok <- authorize_admin(user),
         {:ok, application} <- get_application_or_error(tenant, id),
         {:ok, updated} <- Applications.update_application(application, update_params) do
      render(conn, :updated, application: Repo.preload(updated, :api_keys))
    end
  end

  operation(:delete,
    summary: "Delete application",
    description: """
    Deletes an application and revokes all associated API keys.

    **Requires admin role.**

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
    responses:
      Schemas.Helpers.delete_responses(Schemas.ApplicationDeletedResponse, [
        401,
        403,
        404,
        409,
        429
      ]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Deletes an application and revokes all its API keys.

  Requires admin role.
  """
  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- authorize_admin(user),
         {:ok, application} <- get_application_or_error(tenant, id),
         application <- Repo.preload(application, :api_keys),
         api_key_count <- length(application.api_keys),
         {:ok, :ok} <- delete_application_with_keys(application) do
      render(conn, :deleted, id: id, api_keys_revoked: api_key_count)
    end
  end

  # Authorization helpers

  defp authorize_admin(%User{role: "admin"}), do: :ok
  defp authorize_admin(_user), do: {:error, :forbidden}

  # Application helpers

  defp get_application_or_error(tenant, id) do
    case Applications.get_application_by_tenant(tenant, id) do
      nil -> {:error, :not_found}
      application -> {:ok, application}
    end
  end

  defp create_application_with_key(tenant, params) do
    Repo.transaction(fn ->
      with {:ok, application} <- Applications.create_application(tenant, params),
           {:ok, api_key} <- ApiKeys.create_api_key(application, %{name: "Default"}) do
        {application, api_key}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # Application deletion helpers

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

  # Flop parameter helpers

  @flop_keys ~w(first after last before offset limit order_by order_directions filters)

  defp extract_flop_params(params) do
    params
    |> Map.take(@flop_keys)
    |> maybe_convert_pagination_values()
  end

  defp maybe_convert_pagination_values(params) do
    params
    |> maybe_convert_to_integer("first")
    |> maybe_convert_to_integer("last")
    |> maybe_convert_to_integer("offset")
    |> maybe_convert_to_integer("limit")
  end

  defp maybe_convert_to_integer(params, key) do
    case Map.get(params, key) do
      nil ->
        params

      value when is_integer(value) ->
        params

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> Map.put(params, key, int)
          # Invalid integer string - leave as-is, let Flop validation handle it
          _ -> params
        end
    end
  end

  defp flop_errors_to_map(%Flop.Meta{errors: errors}) do
    Enum.map_join(errors, "; ", fn
      {field, {message, opts}} -> format_error(field, message, opts)
      {field, messages} when is_list(messages) -> format_error_list(field, messages)
    end)
  end

  defp format_error(field, message, opts) do
    formatted_message = format_message(message, opts)
    "#{field}: #{formatted_message}"
  end

  defp format_error_list(field, messages) do
    formatted =
      Enum.map_join(messages, ", ", fn {message, opts} -> format_message(message, opts) end)

    "#{field}: #{formatted}"
  end

  defp format_message(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end
