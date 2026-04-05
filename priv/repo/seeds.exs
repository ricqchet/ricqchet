# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Ricqchet.Repo.insert!(%Ricqchet.SomeSchema{})
#
# This seed file is idempotent - safe to run multiple times.

import Ecto.Query

alias Ricqchet.ApiKeys
alias Ricqchet.Applications
alias Ricqchet.Repo
alias Ricqchet.Tenants
alias Ricqchet.Tenants.Tenant
alias Ricqchet.Users

# Seed data configuration
tenant_name = "Demo Organization"
user_email = "admin@demo.local"

user_password = "password123456"

application_name = "Demo Application"
api_key_name = "Development Key"

IO.puts("\n🌱 Seeding database...\n")

# Find or create tenant
tenant =
  case Repo.one(from t in Tenant, where: t.name == ^tenant_name, limit: 1) do
    nil ->
      {:ok, tenant} = Tenants.create_tenant(%{name: tenant_name})
      IO.puts("✓ Created tenant: #{tenant.name}")
      tenant

    existing ->
      IO.puts("✓ Found existing tenant: #{existing.name}")
      existing
  end

# Find or create user
{user, password_info} =
  case Users.get_user_by_email(user_email) do
    nil ->
      {:ok, user} = Users.create_user(tenant, %{email: user_email, password: user_password})
      {:ok, user} = Users.confirm_user(user)
      IO.puts("✓ Created user: #{user.email} (verified)")
      {user, user_password}

    existing ->
      IO.puts("✓ Found existing user: #{existing.email}")
      {existing, "(unchanged)"}
  end

# Find or create application
application =
  with {:ok, {applications, _meta}} <- Applications.list_applications_for_tenant(tenant),
       nil <- Enum.find(applications, &(&1.name == application_name)) do
    {:ok, application} = Applications.create_application(tenant, %{name: application_name})
    IO.puts("✓ Created application: #{application.name}")
    application
  else
    %Ricqchet.Applications.Application{} = existing ->
      IO.puts("✓ Found existing application: #{existing.name}")
      existing
  end

# Find or create API key
{_api_key, api_key_info} =
  case ApiKeys.list_api_keys_for_application(application)
       |> Enum.find(&(&1.name == api_key_name)) do
    nil ->
      {:ok, api_key} = ApiKeys.create_api_key(application, %{name: api_key_name})
      IO.puts("✓ Created API key: #{api_key.name}")
      {api_key, api_key.api_key}

    existing ->
      IO.puts("✓ Found existing API key: #{existing.name}")
      {existing, "(already exists - cannot retrieve)"}
  end

# Output credentials
IO.puts("""

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SEED DATA CREDENTIALS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Tenant:      #{tenant.name}
  Tenant ID:   #{tenant.id}

  User Email:  #{user.email}
  Password:    #{password_info}

  Application: #{application.name}
  App ID:      #{application.id}

  API Key:     #{api_key_info}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  Save the API key now - it cannot be retrieved later!

""")
