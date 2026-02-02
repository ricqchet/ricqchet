# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Ricqchet.Repo.insert!(%Ricqchet.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Ricqchet.ApiKeys
alias Ricqchet.Applications
alias Ricqchet.Tenants
alias Ricqchet.Users

# Seed data configuration
tenant_name = "Demo Organization"
user_email = "admin@demo.local"
user_password =
  :crypto.strong_rand_bytes(32)
  |> Base.url_encode64(padding: false)
  |> binary_part(0, 24)
application_name = "Demo Application"
api_key_name = "Development Key"

IO.puts("\n🌱 Seeding database...\n")

# Create tenant
{:ok, tenant} = Tenants.create_tenant(%{name: tenant_name})
IO.puts("✓ Created tenant: #{tenant.name}")

# Create user
{:ok, user} = Users.create_user(tenant, %{email: user_email, password: user_password})
IO.puts("✓ Created user: #{user.email}")

# Create application
{:ok, application} = Applications.create_application(tenant, %{name: application_name})
IO.puts("✓ Created application: #{application.name}")

# Create API key
{:ok, api_key} = ApiKeys.create_api_key(application, %{name: api_key_name})
IO.puts("✓ Created API key: #{api_key.name}")

# Output credentials
IO.puts("""

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SEED DATA CREDENTIALS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Tenant:      #{tenant.name}
  Tenant ID:   #{tenant.id}

  User Email:  #{user.email}
  Password:    #{user_password}

  Application: #{application.name}
  App ID:      #{application.id}

  API Key:     #{api_key.api_key}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  Save the API key now - it cannot be retrieved later!

""")
