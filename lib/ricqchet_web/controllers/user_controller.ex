defmodule RicqchetWeb.UserController do
  @moduledoc """
  Controller for user profile endpoints.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["users"])

  operation(:show,
    summary: "Get current user profile",
    description: """
    Returns the profile information for the currently authenticated user.
    """,
    security: [%{"bearerAuth" => []}],
    responses: %{
      200 => {"User profile", "application/json", Schemas.User.UserResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Returns the current user's profile.
  """
  def show(conn, _params) do
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    conn
    |> put_status(:ok)
    |> render(:show, user: user, tenant: tenant)
  end

  operation(:update,
    summary: "Update current user profile",
    description: """
    Updates the profile information for the currently authenticated user.
    Currently no updateable fields are supported through this endpoint.
    """,
    security: [%{"bearerAuth" => []}],
    request_body:
      {"Profile updates", "application/json", Schemas.User.UpdateUserRequest, required: true},
    responses: %{
      200 => {"Updated user profile", "application/json", Schemas.User.UserResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Updates the current user's profile.
  """
  def update(conn, _params) do
    # Currently no updateable fields through this endpoint
    # In the future, add fields like :name, :avatar_url, etc.
    user = conn.assigns.current_user
    tenant = conn.assigns.current_tenant

    conn
    |> put_status(:ok)
    |> render(:show, user: user, tenant: tenant)
  end
end
