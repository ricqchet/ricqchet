defmodule RicqchetWeb.AuthController do
  @moduledoc """
  Controller for authentication endpoints.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Ricqchet.Auth
  alias Ricqchet.Mailer
  alias Ricqchet.Mailer.Email
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["auth"])

  operation(:register,
    summary: "Register a new user",
    description: """
    Creates a new user and organization (tenant). A verification email will be sent
    to the provided email address. The user must verify their email before they can log in.
    """,
    request_body:
      {"Registration details", "application/json", Schemas.Auth.RegisterRequest, required: true},
    responses: %{
      201 => {"Registration successful", "application/json", Schemas.Auth.RegisterResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Registers a new user and creates their tenant.
  """
  def register(conn, params) do
    with {:ok, %{user: user, verification_token: token}} <- Auth.register_user(params) do
      # Send verification email
      verification_url = build_verification_url(token)

      user.email
      |> Email.verification_email(verification_url)
      |> Mailer.deliver()

      conn
      |> put_status(:created)
      |> render(:registered, user: user)
    end
  end

  defp build_verification_url(token) do
    base_url = Application.get_env(:ricqchet, :frontend_url, "http://localhost:4000")
    "#{base_url}/verify-email?token=#{token}"
  end
end
