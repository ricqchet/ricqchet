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

  operation(:forgot_password,
    summary: "Request password reset",
    description: """
    Initiates a password reset by sending a reset link to the provided email address.
    For security reasons, this endpoint always returns success, even if the email
    doesn't exist in the system (to prevent email enumeration).
    """,
    request_body:
      {"Email address", "application/json", Schemas.Auth.ForgotPasswordRequest, required: true},
    responses: %{
      200 =>
        {"Reset email sent (if account exists)", "application/json", Schemas.Auth.MessageResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Requests a password reset for the given email.
  """
  def forgot_password(conn, %{"email" => email}) do
    case Auth.request_password_reset(email) do
      {:ok, nil} ->
        # Email doesn't exist, but we return success to prevent enumeration
        render_password_reset_response(conn)

      {:ok, %{user: user, reset_token: token}} ->
        # Send password reset email with error handling to prevent crashes
        reset_url = build_reset_url(token)
        send_password_reset_email(user.email, reset_url)
        render_password_reset_response(conn)

      {:error, _reason} ->
        # Log the error but still return success to prevent enumeration
        require Logger
        Logger.error("Failed to create password reset token for email")
        render_password_reset_response(conn)
    end
  end

  def forgot_password(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_error", message: "Email is required"})
  end

  defp send_password_reset_email(email, reset_url) do
    email
    |> Email.password_reset_email(reset_url)
    |> Mailer.deliver()
  rescue
    error ->
      require Logger
      Logger.error("Failed to send password reset email: #{inspect(error)}")
      :error
  end

  defp render_password_reset_response(conn) do
    conn
    |> put_status(:ok)
    |> render(:message,
      message: "If an account exists with that email, a password reset link has been sent"
    )
  end

  operation(:reset_password,
    summary: "Complete password reset",
    description: """
    Completes a password reset using the token received via email. The token must be
    valid and not expired (tokens expire after 1 hour). After a successful reset,
    all existing sessions are invalidated.
    """,
    request_body:
      {"Reset token and new password", "application/json", Schemas.Auth.ResetPasswordRequest,
       required: true},
    responses: %{
      200 => {"Password reset successful", "application/json", Schemas.Auth.MessageResponse},
      400 => {"Invalid or expired token", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Resets a user's password using a valid reset token.
  """
  def reset_password(conn, %{"token" => token, "password" => password}) do
    case Auth.reset_password(token, password) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> render(:message,
          message:
            "Password has been reset successfully. You can now log in with your new password."
        )

      {:error, :invalid_token} ->
        {:error, :bad_request, "Invalid password reset token"}

      {:error, :token_expired} ->
        {:error, :bad_request, "Password reset token has expired"}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  def reset_password(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_error", message: "Token and password are required"})
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

  operation(:accept_invite,
    summary: "Accept tenant invitation",
    description: """
    Accepts an invitation to join a tenant. Creates a new user account if the email
    doesn't exist, or adds the existing user to the tenant. Returns JWT tokens for
    immediate authentication.
    """,
    request_body:
      {"Invitation acceptance", "application/json", Schemas.Auth.AcceptInviteRequest,
       required: true},
    responses: %{
      200 => {"Invitation accepted", "application/json", Schemas.Auth.AcceptInviteResponse},
      400 => {"Invalid or expired token", "application/json", Schemas.ErrorResponse},
      422 => {"Validation error", "application/json", Schemas.ErrorResponse}
    }
  )

  @doc """
  Accepts an invitation to join a tenant.
  """
  def accept_invite(conn, %{"token" => token, "password" => password}) do
    case Auth.accept_invitation(token, password) do
      {:ok, auth_data} ->
        conn
        |> put_status(:ok)
        |> render(:logged_in, auth_data)

      {:error, :invalid_token} ->
        {:error, :invalid_token}

      {:error, :token_expired} ->
        {:error, :token_expired}

      {:error, :invitation_not_pending} ->
        {:error, :invitation_not_pending}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  def accept_invite(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_error", message: "Token and password are required"})
  end

  defp build_verification_url(token) do
    base_url = Application.get_env(:ricqchet, :frontend_url, "http://localhost:4000")
    "#{base_url}/verify-email?token=#{token}"
  end

  defp build_reset_url(token) do
    base_url = Application.get_env(:ricqchet, :frontend_url, "http://localhost:4000")
    "#{base_url}/reset-password?token=#{token}"
  end
end
