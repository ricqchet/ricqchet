# Authentication

Ricqchet uses a multi-tenant architecture with API key authentication.

## Architecture

```
Tenant (Organization)
  └── Application
        └── API Key(s)
```

- **Tenant**: Top-level organization or account
- **Application**: A project or service within a tenant
- **API Key**: Authentication credential for an application

## Setup

### 1. Create a Tenant

```elixir
# In iex -S mix
alias Ricqchet.Tenants

{:ok, tenant} = Tenants.create_tenant(%{name: "My Organization"})
```

### 2. Create an Application

```elixir
alias Ricqchet.Applications

{:ok, application} = Applications.create_application(tenant, %{
  name: "Production API",
  description: "Main production service"
})
```

### 3. Create an API Key

```elixir
alias Ricqchet.ApiKeys

{:ok, api_key} = ApiKeys.create_api_key(application, %{name: "Production Key"})

# IMPORTANT: Save this value - it's only shown once!
IO.puts("API Key: #{api_key.api_key}")
```

The plaintext API key is only available immediately after creation. Store it securely.

## Using API Keys

Include the API key in the `Authorization` header:

```bash
curl -X POST "http://localhost:4000/v1/publish/https://example.com/webhook" \
  -H "Authorization: Bearer <your_api_key>" \
  -H "Content-Type: application/json" \
  -d '{"event": "test"}'
```

## API Key Management

### List Keys for an Application

```elixir
ApiKeys.list_api_keys_for_application(application)
```

### Revoke a Key

```elixir
ApiKeys.revoke_api_key(api_key)
```

Revoked keys are immediately invalidated and cannot be used for authentication.

### Rotate a Key

```elixir
{:ok, new_api_key} = ApiKeys.rotate_api_key(old_api_key)

# The old key is revoked, save the new one
IO.puts("New API Key: #{new_api_key.api_key}")
```

Rotation atomically revokes the old key and creates a new one with the same name.

## Key Expiration

API keys can have an optional expiration date. Expired keys are automatically rejected during authentication.

## Security

- API keys are hashed using Argon2 before storage
- Only an 8-character prefix is stored for O(1) lookup
- Verification uses constant-time comparison to prevent timing attacks
- Keys are scoped to applications, and applications are scoped to tenants
- Inactive tenants or applications will reject all associated API keys

## Tenant Status

Tenants can have the following statuses:

| Status | Description |
|--------|-------------|
| `active` | Normal operation, all API keys work |
| `suspended` | All API requests are rejected |

## Application Status

Applications can have the following statuses:

| Status | Description |
|--------|-------------|
| `active` | Normal operation |
| `inactive` | API keys for this application are rejected |
