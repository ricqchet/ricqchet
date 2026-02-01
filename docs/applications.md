# Applications

Applications represent software or services within a tenant that can use the Ricqchet API. Each application can have multiple API keys for authentication.

## Overview

```
Tenant (Organization)
  └── Application ← You are here
        └── API Key(s)
```

Applications provide:
- **Isolation**: Each application has its own API keys and message history
- **Configuration**: Per-application DLQ destination URL
- **Management**: Create, update, suspend, or delete applications via API

## API Endpoints

All application endpoints require authentication via Bearer token.

### List Applications

```
GET /v1/applications
```

Returns all applications for the current tenant.

**Example:**

```bash
curl "http://localhost:4000/v1/applications" \
  -H "Authorization: Bearer <api_key>"
```

**Response (200 OK):**

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Production API",
      "description": "Main production service",
      "status": "active",
      "dlq_destination_url": "https://example.com/dlq",
      "api_key_count": 2,
      "created_at": "2026-01-15T10:00:00Z",
      "updated_at": "2026-01-20T14:30:00Z"
    }
  ],
  "meta": {
    "total": 1
  }
}
```

### Get Application

```
GET /v1/applications/{id}
```

Returns detailed information about an application, including its API keys (with secrets redacted).

**Example:**

```bash
curl "http://localhost:4000/v1/applications/550e8400-..." \
  -H "Authorization: Bearer <api_key>"
```

**Response (200 OK):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "Production API",
  "description": "Main production service",
  "status": "active",
  "dlq_destination_url": "https://example.com/dlq",
  "api_keys": [
    {
      "id": "660e8400-e29b-41d4-a716-446655440001",
      "name": "Production Key",
      "prefix": "rq_live_",
      "status": "active",
      "last_used_at": "2026-01-31T15:30:00Z",
      "expires_at": null,
      "created_at": "2026-01-15T10:00:00Z"
    }
  ],
  "created_at": "2026-01-15T10:00:00Z",
  "updated_at": "2026-01-20T14:30:00Z"
}
```

### Create Application

```
POST /v1/applications
```

Creates a new application with a default API key.

**Important:** The API key is only shown once in the response. Store it securely.

**Request Body:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Application name (max 255 characters) |
| `description` | string | No | Optional description (max 255 characters) |
| `dlq_destination_url` | string | No | Dead letter queue URL (must be HTTPS) |

**Example:**

```bash
curl -X POST "http://localhost:4000/v1/applications" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My New Application",
    "description": "Handles order webhooks"
  }'
```

**Response (201 Created):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "My New Application",
  "description": "Handles order webhooks",
  "status": "active",
  "dlq_destination_url": null,
  "api_key": "rq_live_abc123def456...",
  "created_at": "2026-01-31T10:00:00Z"
}
```

### Update Application

```
PATCH /v1/applications/{id}
```

Updates an application's name, description, status, or DLQ destination.

**Request Body:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | New application name |
| `description` | string | New description |
| `status` | string | `active` or `suspended` |
| `dlq_destination_url` | string | New DLQ URL (must be HTTPS) |

**Example:**

```bash
curl -X PATCH "http://localhost:4000/v1/applications/550e8400-..." \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{
    "status": "suspended"
  }'
```

**Response (200 OK):**

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "My New Application",
  "description": "Handles order webhooks",
  "status": "suspended",
  "dlq_destination_url": null,
  "api_keys": [...],
  "created_at": "2026-01-31T10:00:00Z",
  "updated_at": "2026-01-31T11:00:00Z"
}
```

### Delete Application

```
DELETE /v1/applications/{id}
```

Deletes an application and revokes all associated API keys.

**Warning:** This action is irreversible. All API keys will be immediately revoked and any requests using those keys will fail.

**Example:**

```bash
curl -X DELETE "http://localhost:4000/v1/applications/550e8400-..." \
  -H "Authorization: Bearer <api_key>"
```

**Response (200 OK):**

```json
{
  "deleted": true,
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "api_keys_revoked": 2
}
```

## Application Status

| Status | Description |
|--------|-------------|
| `active` | Normal operation, API keys work |
| `suspended` | All API requests using this application's keys are rejected |

## Dead Letter Queue (DLQ)

Each application can have a DLQ destination URL for failed messages. See [DLQ documentation](dlq.md) for details.

**Example: Setting DLQ on create:**

```bash
curl -X POST "http://localhost:4000/v1/applications" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Production API",
    "dlq_destination_url": "https://errors.example.com/dlq"
  }'
```

## Error Responses

| Status | Error | Description |
|--------|-------|-------------|
| 401 | `unauthorized` | Invalid or missing API key |
| 404 | `not_found` | Application not found or belongs to another tenant |
| 422 | `validation_error` | Invalid request body (e.g., missing name, invalid URL) |
| 429 | - | Rate limit exceeded |
