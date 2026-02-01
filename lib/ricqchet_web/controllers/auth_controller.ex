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

  operation(:verify_email,
    summary: "Verify email address",
    description: """
    Verifies the user's email address using the token sent via email.
    Once verified, the user can log in to their account.
    """,
    request_body:
      {"Verification token", "application/json", Schemas.Auth.VerifyEmailRequest, required: true},
    responses: %{
      200 => {"Email verified", "application/json", Schemas.Auth.VerifyEmailResponse},
      400 => {"Invalid or expired token", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Verifies a user's email address using the verification token.
  """
  def verify_email(conn, %{"token" => token}) do
    case Auth.verify_email(token) do
      {:ok, user} ->
        conn
        |> put_status(:ok)
        |> render(:email_verified, user: user)

      {:error, :invalid_token} ->
        {:error, :bad_request, "Invalid verification token"}

      {:error, :token_expired} ->
        {:error, :bad_request, "Verification token has expired"}
    end
  end

  def verify_email(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_error", message: "Token is required"})
  end

  operation(:resend_verification,
    summary: "Resend verification email",
    description: """
    Resends the email verification link to the authenticated user's email address.
    Use this if the original verification email was not received or has expired.
    """,
    security: [%{"bearerAuth" => []}],
    responses: %{
      200 => {"Verification email sent", "application/json", Schemas.Auth.MessageResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse},
      400 => {"Email already verified", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Resends the email verification link to the authenticated user.
  """
  def resend_verification(conn, _params) do
    user = conn.assigns.current_user

    if user.confirmed_at do
      {:error, :bad_request, "Email is already verified"}
    else
      {:ok, verification_token} = Auth.create_email_verification_token(user)
      verification_url = build_verification_url(verification_token.token)

      user.email
      |> Email.verification_email(verification_url)
      |> Mailer.deliver()

      conn
      |> put_status(:ok)
      |> render(:message, message: "Verification email has been sent")
    end
  end

  defp build_verification_url(token) do
    base_url = Application.get_env(:ricqchet, :frontend_url, "http://localhost:4000")
    "#{base_url}/verify-email?token=#{token}"
  end
end
