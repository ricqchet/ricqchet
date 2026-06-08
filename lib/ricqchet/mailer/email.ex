defmodule Ricqchet.Mailer.Email do
  @moduledoc """
  Email templates for authentication-related emails.
  """

  import Swoosh.Email

  @from_email "noreply@ricqchet.io"
  @from_name "Ricqchet"

  @doc """
  Builds a password reset email.

  ## Parameters

  - `to_email` - Recipient email address
  - `reset_url` - Full URL for the password reset link

  ## Example

      Email.password_reset_email("user@example.com", "https://app.ricqchet.io/reset?token=abc")
  """
  def password_reset_email(to_email, reset_url) do
    new()
    |> to(to_email)
    |> from({@from_name, @from_email})
    |> subject("Reset your password")
    |> text_body("""
    You requested a password reset for your Ricqchet account.

    Click the link below to reset your password:

    #{reset_url}

    This link will expire in 1 hour.

    If you did not request a password reset, you can safely ignore this email.

    Thanks,
    The Ricqchet Team
    """)
    |> html_body("""
    <h1>Reset Your Password</h1>

    <p>You requested a password reset for your Ricqchet account.</p>

    <p>Click the link below to reset your password:</p>

    <p><a href="#{reset_url}">Reset Password</a></p>

    <p>Or copy and paste this URL into your browser:</p>
    <p>#{reset_url}</p>

    <p>This link will expire in 1 hour.</p>

    <p>If you did not request a password reset, you can safely ignore this email.</p>

    <p>Thanks,<br>The Ricqchet Team</p>
    """)
  end
end
