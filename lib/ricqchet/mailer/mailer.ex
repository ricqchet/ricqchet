defmodule Ricqchet.Mailer do
  @moduledoc """
  Swoosh mailer for sending emails.

  Configured with different adapters per environment:
  - Development: Swoosh.Adapters.Local (viewable at /dev/mailbox)
  - Test: Swoosh.Adapters.Test
  - Production: Configure via runtime.exs (SMTP, Mailgun, etc.)
  """

  use Swoosh.Mailer, otp_app: :ricqchet
end
