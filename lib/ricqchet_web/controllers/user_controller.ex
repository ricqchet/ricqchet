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
end
