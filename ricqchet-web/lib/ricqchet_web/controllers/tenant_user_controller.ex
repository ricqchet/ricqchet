defmodule RicqchetWeb.TenantUserController do
  @moduledoc """
  Controller for tenant user management.

  Provides endpoints for listing, inviting, updating, and removing users within a tenant.

  ## Authorization

  - **List**: Any authenticated user
  - **Create/Update/Delete**: Admin only
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.Authorization
  alias Ricqchet.Tenants
  alias Ricqchet.Users
  alias Ricqchet.Users.User
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["tenant users"])

  operation(:index,
    summary: "List tenant users",
    description: """
    Returns a paginated list of users in the current tenant.

    Supports cursor-based pagination (recommended for large datasets):
    - `first` + optional `after` cursor for forward pagination
    - `last` + optional `before` cursor for backward pagination

    Or offset-based pagination:
    - `offset` + `limit`

    **Filtering:**
    - `filters[0][field]=email&filters[0][op]=ilike&filters[0][value]=example.com`
    - `filters[0][field]=role&filters[0][value]=admin`
    - `filters[0][field]=status&filters[0][value]=active`

    **Sorting:**
    - `order_by[]=email&order_directions[]=asc`
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
        description: "Cursor for forward pagination"
      ],
      last: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 100},
        description: "Number of items to return (backward pagination)"
      ],
      before: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Cursor for backward pagination"
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
          items: %Schema{
            type: :string,
            enum: ~w(email role status inserted_at updated_at last_login_at)
          }
        },
        description: "Fields to sort by"
      ],
      order_directions: [
        in: :query,
        schema: %Schema{type: :array, items: %Schema{type: :string, enum: ~w(asc desc)}},
        description: "Sort directions for each order_by field"
      ],
      filters: [
        in: :query,
        schema: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              field: %Schema{type: :string, enum: ~w(email role status)},
              op: %Schema{type: :string, enum: ~w(== != =~ ilike like empty not_empty)},
              value: %Schema{type: :string}
            }
          }
        },
        description: "Array of filters"
      ]
    ],
    responses: Schemas.Helpers.list_responses(Schemas.Tenant.UserList, [401, 422, 429]),
    security: [%{"bearerAuth" => []}]
  )

  @doc """
  Lists users in the current tenant with pagination.
  """
  def index(conn, params) do
    tenant = conn.assigns.current_tenant
    flop_params = extract_flop_params(params)

    case Users.list_users_for_tenant_paginated(tenant, flop_params) do
      {:ok, {users, meta}} ->
        render(conn, :index, users: users, meta: meta)

      {:error, meta} ->
        {:error, :validation, flop_errors_to_map(meta)}
    end
  end

  operation(:create,
    summary: "Create a user",
    description: """
    Creates a new user account on this instance.

    If `password` is omitted, the server generates a secure password and returns
    it once in the response as `password` — store it immediately, as it cannot be
    retrieved later. Share the credentials with the user out of band.

    The account is created active and confirmed; there is no email-verification step.

    **Requires admin role.**
    """,
    request_body:
      {"User parameters", "application/json", Schemas.Tenant.CreateUserRequest, required: true},
    responses:
      Schemas.Helpers.create_responses(Schemas.Tenant.CreateUserResponse, 201, [
        401,
        403,
        409,
        422,
        429
      ]),
    security: [%{"bearerAuth" => []}]
  )

  @doc """
  Creates a new user. Requires admin role.
  """
  def create(conn, params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant
    user_params = Map.take(params, ["email", "role", "password"])

    with :ok <- Authorization.authorize(user, :admin),
         {:ok, created_user, generated_password} <-
           Users.create_user_by_admin(tenant, user_params) do
      conn
      |> put_status(:created)
      |> render(:created, user: created_user, password: generated_password)
    end
  end

  operation(:update,
    summary: "Update user role",
    description: """
    Changes a user's role within the tenant.

    **Requires admin role.**

    Cannot demote yourself if you are the last admin.
    """,
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "User ID"
      ]
    ],
    request_body:
      {"User update parameters", "application/json", Schemas.Tenant.UpdateUserRoleRequest,
       required: true},
    responses:
      Schemas.Helpers.update_responses(Schemas.Tenant.UserResponse, [401, 403, 404, 422, 429]),
    security: [%{"bearerAuth" => []}]
  )

  @doc """
  Updates a user's role within the tenant.

  Requires admin role. Cannot demote self if last admin.
  """
  def update(conn, %{"id" => user_id} = params) do
    current_user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant
    update_params = Map.take(params, ["role"])

    with :ok <- Authorization.authorize(current_user, :admin),
         {:ok, target_user} <- get_tenant_user(tenant, user_id),
         :ok <- validate_role_change(current_user, target_user, update_params, tenant),
         {:ok, updated_user} <- Users.update_user(target_user, update_params) do
      render(conn, :show, user: updated_user)
    end
  end

  operation(:delete,
    summary: "Remove user from tenant",
    description: """
    Removes a user from the current tenant.

    **Requires admin role.**

    Cannot remove yourself or the last admin.
    """,
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "User ID"
      ]
    ],
    responses:
      Schemas.Helpers.delete_responses(Schemas.Tenant.UserRemovedResponse, [401, 403, 404, 429]),
    security: [%{"bearerAuth" => []}]
  )

  @doc """
  Removes a user from the current tenant.

  Requires admin role. Cannot remove self or last admin.
  """
  def delete(conn, %{"id" => user_id}) do
    current_user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    with :ok <- Authorization.authorize(current_user, :admin),
         {:ok, target_user} <- get_tenant_user(tenant, user_id),
         :ok <- validate_not_self(current_user, target_user),
         :ok <- validate_not_last_admin(target_user, tenant),
         {:ok, _user} <- Tenants.remove_user_from_tenant(target_user) do
      render(conn, :deleted, id: user_id)
    end
  end

  # Authorization helpers

  defp get_tenant_user(tenant, user_id) do
    case Users.get_user_by_tenant(tenant, user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp validate_not_self(%User{id: id}, %User{id: id}), do: {:error, :cannot_remove_self}
  defp validate_not_self(_current, _target), do: :ok

  defp validate_not_last_admin(%User{role: "admin"} = _target_user, tenant) do
    case Tenants.count_admins(tenant) do
      1 -> {:error, :cannot_remove_last_admin}
      _ -> :ok
    end
  end

  defp validate_not_last_admin(_target_user, _tenant), do: :ok

  defp validate_role_change(current_user, target_user, %{"role" => new_role}, tenant) do
    # Check if demoting self from admin
    demoting_self_from_admin? =
      current_user.id == target_user.id and target_user.role == "admin" and new_role != "admin"

    if demoting_self_from_admin? do
      case Tenants.count_admins(tenant) do
        1 -> {:error, :cannot_demote_last_admin}
        _ -> :ok
      end
    else
      :ok
    end
  end

  defp validate_role_change(_current_user, _target_user, _params, _tenant), do: :ok

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
