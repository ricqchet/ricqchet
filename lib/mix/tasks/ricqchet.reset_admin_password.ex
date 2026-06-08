defmodule Mix.Tasks.Ricqchet.ResetAdminPassword do
  @shortdoc "Resets (or sets) an admin password without sending email"

  @moduledoc """
  Resets the password for an admin account on a self-hosted instance, for
  recovery when no mailer is configured.

      mix ricqchet.reset_admin_password [email]

  If no email is given, `ADMIN_EMAIL` is used (default `admin@localhost`).
  Set `ADMIN_PASSWORD` to choose the new password; otherwise a secure password
  is generated and printed.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    email = List.first(args)
    Ricqchet.Release.reset_admin_password(email)
  end
end
