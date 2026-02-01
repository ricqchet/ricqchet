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

  operation(:login,
    summary: "Log in a user",
    description: """
    Authenticates a user with email and password. Returns access and refresh tokens
    on success. The user must have a verified email address to log in.
    """,
    request_body:
      {"Login credentials", "application/json", Schemas.Auth.LoginRequest, required: true},
    responses: %{
      200 => {"Login successful", "application/json", Schemas.Auth.LoginResponse},
      401 =>
        {"Invalid credentials or email not verified", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Authenticates a user and returns access and refresh tokens.
  """
  def login(conn, %{"email" => email, "password" => password}) do
    case Auth.login(email, password) do
      {:ok, auth_data} ->
        conn
        |> put_status(:ok)
        |> render(:logged_in, auth_data)

      {:error, :invalid_credentials} ->
        {:error, :unauthorized, "Invalid email or password"}

      {:error, :email_not_verified} ->
        {:error, :unauthorized, "Please verify your email address before logging in"}
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_error", message: "Email and password are required"})
  end

  operation(:logout,
    summary: "Log out a user",
    description: """
    Revokes the provided refresh token. Optionally revoke all sessions by setting
    `everywhere: true`, which invalidates all tokens for the user.
    """,
    security: [%{"bearerAuth" => []}],
    request_body:
      {"Logout options", "application/json", Schemas.Auth.LogoutRequest, required: true},
    responses: %{
      200 => {"Logged out successfully", "application/json", Schemas.Auth.MessageResponse},
      401 => {"Unauthorized", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Logs out a user by revoking their refresh token.
  """
  def logout(conn, params) do
    refresh_token = params["refresh_token"]
    everywhere = params["everywhere"] == true

    case Auth.logout(refresh_token, everywhere: everywhere) do
      :ok ->
        message =
          if everywhere,
            do: "Logged out from all sessions",
            else: "Logged out successfully"

        conn
        |> put_status(:ok)
        |> render(:message, message: message)

      {:error, _reason} ->
        # Still return success even if token not found (idempotent logout)
        conn
        |> put_status(:ok)
        |> render(:message, message: "Logged out successfully")
    end
  end

  operation(:refresh,
    summary: "Refresh access token",
    description: """
    Exchanges a valid refresh token for a new access token. The refresh token
    must be valid (not expired or revoked) and the user's token version must match.
    """,
    request_body:
      {"Refresh token", "application/json", Schemas.Auth.RefreshRequest, required: true},
    responses: %{
      200 => {"Token refreshed", "application/json", Schemas.Auth.RefreshResponse},
      401 => {"Invalid refresh token", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Refreshes an access token using a valid refresh token.
  """
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    case Auth.refresh_access_token(refresh_token) do
      {:ok, token_data} ->
        conn
        |> put_status(:ok)
        |> render(:refreshed, token_data)

      {:error, :invalid_refresh_token} ->
        {:error, :unauthorized, "Invalid or expired refresh token"}
    end
  end

  def refresh(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_error", message: "Refresh token is required"})
  end

  operation(:change_password,
    summary: "Change password",
    description: """
    Changes the user's password. Requires the current password for verification.
    After a successful password change, all existing sessions are invalidated and
    new tokens are returned for the current session.
    """,
    security: [%{"bearerAuth" => []}],
    request_body:
      {"Password change details", "application/json", Schemas.Auth.ChangePasswordRequest,
       required: true},
    responses: %{
      200 => {"Password changed", "application/json", Schemas.Auth.LoginResponse},
      401 => {"Invalid current password", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Changes the user's password.
  """
  def change_password(conn, %{"current_password" => current, "new_password" => new}) do
    user = conn.assigns.current_user

    case Auth.change_password(user, current, new) do
      {:ok, auth_data} ->
        conn
        |> put_status(:ok)
        |> render(:logged_in, auth_data)

      {:error, :invalid_current_password} ->
        {:error, :unauthorized, "Current password is incorrect"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  def change_password(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "validation_error",
      message: "Current password and new password are required"
    })
  end

  defp build_verification_url(token) do
    base_url = Application.get_env(:ricqchet, :frontend_url, "http://localhost:4000")
    "#{base_url}/verify-email?token=#{token}"
  end
end
