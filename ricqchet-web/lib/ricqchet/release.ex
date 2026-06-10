defmodule Ricqchet.Release do
  @moduledoc """
  Release and first-run bootstrap tasks for self-hosted Ricqchet.

  In an OTP release these run via `bin/ricqchet eval`:

      bin/ricqchet eval "Ricqchet.Release.migrate()"
      bin/ricqchet eval "Ricqchet.Release.seed()"

  In development the same logic runs through `mix ecto.setup`, whose seed step
  (`priv/repo/seeds.exs`) calls `bootstrap/0`.

  ## Initial admin

  `seed/0` (and `bootstrap/0`) ensures the single default tenant and one admin
  user exist. The admin is configured via environment variables:

    * `ADMIN_EMAIL`    - the admin's email (default `admin@localhost`)
    * `ADMIN_PASSWORD` - the admin's password (12-72 characters); if unset, a
      secure password is generated and printed once

  Both functions are idempotent: if an admin already exists they make no changes.
  """

  # This task prints initial admin credentials and reset output directly to the
  # console on purpose (an operator must see them, even outside the logger), so
  # IO.puts is the right tool here.
  # credo:disable-for-this-file Credo.Check.Refactor.IoPuts

  require Logger

  alias Ricqchet.Repo
  alias Ricqchet.Tenants
  alias Ricqchet.Tenants.Tenant
  alias Ricqchet.Users

  @app :ricqchet
  @default_tenant_name "Default"
  @default_admin_email "admin@localhost"

  @doc """
  Runs all pending migrations. Intended for OTP releases.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Rolls a repo back to the given migration version.
  """
  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Ensures the default tenant and initial admin exist. Intended for OTP releases
  (manages the repo lifecycle itself). Idempotent.
  """
  def seed do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(Repo, fn _repo -> bootstrap() end)
    :ok
  end

  @doc """
  Resets (or sets) the password for an admin account without sending email.

  Use this to recover a locked-out instance. Reads `ADMIN_PASSWORD` if set,
  otherwise generates and prints a secure password. Falls back to `ADMIN_EMAIL`
  when no email is given.
  """
  def reset_admin_password(email \\ nil) do
    load_app()
    target = email || admin_email()
    {:ok, _, _} = Ecto.Migrator.with_repo(Repo, fn _repo -> do_reset_password(target) end)
    :ok
  end

  @doc """
  Ensures the default tenant and initial admin exist, using the already-started
  repo. Called from `priv/repo/seeds.exs` (where the app is already running).
  """
  def bootstrap do
    tenant = ensure_default_tenant!()
    ensure_admin!(tenant)
    :ok
  end

  # Tenant / admin bootstrap

  defp ensure_default_tenant! do
    case Repo.get_by(Tenant, name: @default_tenant_name) do
      nil ->
        {:ok, tenant} = Tenants.create_tenant(%{name: @default_tenant_name})
        tenant

      tenant ->
        tenant
    end
  end

  defp ensure_admin!(tenant) do
    if Tenants.count_admins(tenant) == 0 do
      create_admin!(tenant)
    else
      Logger.info("Ricqchet bootstrap: admin already exists, skipping creation")
    end
  end

  defp create_admin!(tenant) do
    email = admin_email()
    supplied_password = System.get_env("ADMIN_PASSWORD")

    attrs = maybe_put_password(%{"email" => email, "role" => "admin"}, supplied_password)

    case Users.create_user_by_admin(tenant, attrs) do
      {:ok, user, generated_password} ->
        print_credentials(user.email, supplied_password || generated_password,
          generated: is_nil(supplied_password)
        )

        user

      {:error, :user_already_exists} ->
        raise "Cannot create default admin: a user with #{email} already exists. " <>
                "Use `mix ricqchet.reset_admin_password #{email}` to recover access."

      {:error, %Ecto.Changeset{} = changeset} ->
        raise "Failed to create default admin (#{email}): #{inspect(changeset.errors)}"
    end
  end

  defp do_reset_password(email) do
    case Users.get_user_by_email(email) do
      nil ->
        IO.puts("No user found with email #{email}.")
        {:error, :not_found}

      user ->
        supplied_password = System.get_env("ADMIN_PASSWORD")
        password = supplied_password || generate_password()

        case Users.update_password(user, password) do
          {:ok, _user} ->
            print_reset(email, password, generated: is_nil(supplied_password))
            :ok

          {:error, %Ecto.Changeset{} = changeset} ->
            IO.puts(
              "Failed to reset password for #{email}: #{inspect(changeset.errors)}. " <>
                "ADMIN_PASSWORD must be 12-72 characters."
            )

            {:error, changeset}
        end
    end
  end

  defp maybe_put_password(attrs, nil), do: attrs
  defp maybe_put_password(attrs, password), do: Map.put(attrs, "password", password)

  defp admin_email, do: System.get_env("ADMIN_EMAIL", @default_admin_email)

  defp generate_password do
    18
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp print_credentials(email, password, generated: generated) do
    IO.puts("""

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      RICQCHET — DEFAULT ADMIN CREATED
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      Email:     #{email}
    #{password_line(password, generated)}

      ▸ Sign in at /login, then change this password immediately in
        Settings → Change password (or POST /v1/auth/change-password).
      ▸ Locked out later? Reset without email:
          mix ricqchet.reset_admin_password #{email}
        (release: bin/ricqchet eval 'Ricqchet.Release.reset_admin_password("#{email}")')

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    """)
  end

  defp print_reset(email, password, generated: generated) do
    IO.puts("""

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
      RICQCHET — PASSWORD RESET
    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

      Email:     #{email}
    #{password_line(password, generated)}

      ▸ Sign in and change it again from Settings → Change password.

    ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    """)
  end

  defp password_line(_password, false), do: "  Password:  (set via ADMIN_PASSWORD)"

  defp password_line(password, true),
    do: "  Password:  #{password}   (randomly generated — change it now)"

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load_app, do: Application.load(@app)
end
