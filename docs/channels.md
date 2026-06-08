# Channels

Channels provide real-time event broadcasting via WebSocket connections. Events published through the REST API are instantly pushed to all connected clients subscribed to the channel.

## Connection

Connect via WebSocket with your API key:

```
wss://api.ricqchet.com/channels?api_key=<key>&user_id=<uid>&user_info=<json>
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `api_key` | Yes | API key for the application |
| `user_id` | No | Unique user identifier (default: "anonymous") |
| `user_info` | No | JSON-encoded user metadata |

## Subscribing to Channels

After connecting, join a channel using its **bare name** as the topic — there is
no application prefix to construct. The application is resolved from your API key,
so two applications can use the same channel name without colliding.

```javascript
import { Socket } from "phoenix"

const socket = new Socket("wss://api.ricqchet.com/channels", {
  params: { api_key: "your_api_key", user_id: "user-123" }
})
socket.connect()

// Public channel
const chat = socket.channel("chat-room")
chat.join()
chat.on("new-message", (payload) => console.log(payload.data))

// Private / presence channels (require auth endpoint approval)
socket.channel("private-orders").join()
socket.channel("presence-lobby").join()

// Hierarchical names are allowed
socket.channel("orders.us.west").join()
```

## Channel Types

Channel type is determined by the name prefix:

| Type | Prefix | Auth Required | Member Tracking |
|------|--------|---------------|-----------------|
| Public | (none) | No | No |
| Private | `private-` | Yes | No |
| Presence | `presence-` | Yes | Yes |

Channel names must be 1-164 characters of letters, digits, dashes, underscores, or
dots. Use dots for hierarchical names (e.g. `orders.us.west`).

## Publishing Events

### Single Channel

```bash
curl -X POST "http://localhost:4000/v1/channels/events" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{"channel": "chat-room", "event": "new-message", "data": {"text": "Hello!"}}'
```

### Multiple Channels

```bash
curl -X POST "http://localhost:4000/v1/channels/events" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{"channels": ["room-1", "room-2"], "event": "announcement", "data": {"text": "Hi"}}'
```

### Batch Publishing

Publish up to 10 events in a single request:

```bash
curl -X POST "http://localhost:4000/v1/channels/events/batch" \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{"batch": [
    {"channel": "chat", "event": "msg", "data": {"text": "hello"}},
    {"channel": "alerts", "event": "notify", "data": {"level": "info"}}
  ]}'
```

### Sender Exclusion

Pass `socket_id` to prevent the sender from receiving their own event:

```json
{"channel": "chat", "event": "typing", "data": {}, "socket_id": "123.456"}
```

## Private and Presence Channel Authorization

Private and presence channels require an auth endpoint configured on your application or namespace. When a client joins, Ricqchet sends a POST to your auth endpoint:

```json
{
  "channel_name": "private-room",
  "user_id": "user-123",
  "socket_id": "channel_socket:app_id:user-123"
}
```

Return `200` to allow access or any other status to deny it.

## Presence Channels

Presence channels track connected members. When a client joins a `presence-` channel:

1. Their presence is tracked with `user_id` and `user_info`
2. Existing members receive a `presence_diff` event
3. The joining client receives the full `presence_state`

### Query Members via API

```bash
curl "http://localhost:4000/v1/channels/presence-room/members" \
  -H "Authorization: Bearer <api_key>"
```

## Client Events

Connected clients on private and presence channels can send events directly to other clients:

- Event names must start with `client-`
- Rate limited per user (configurable via namespace, default: 10/second)
- Not persisted to history

## Event History

When a namespace has `history_enabled: true`, events are persisted and can be queried:

```bash
# Recent events
curl "http://localhost:4000/v1/channels/chat-room/events?limit=50" \
  -H "Authorization: Bearer <api_key>"

# Events since a specific event
curl "http://localhost:4000/v1/channels/chat-room/events?since_id=<event_id>" \
  -H "Authorization: Bearer <api_key>"
```

### Missed-Message Recovery

Clients can rejoin with `last_event_id` to recover events missed during a disconnect:

```javascript
channel.join({last_event_id: "550e8400-..."})
```

## Cache Channels

When a namespace has `cache_enabled: true`, new subscribers automatically receive the last event published to the channel. This is useful for channels that represent current state (e.g., stock prices, status indicators).

## Namespace Configuration

Namespaces define pattern-based configuration for channels. Managed via the dashboard API:

```bash
curl -X POST "http://localhost:4000/v1/applications/{app_id}/channel-namespaces" \
  -H "Authorization: Bearer <jwt_token>" \
  -H "Content-Type: application/json" \
  -d '{
    "pattern": "chat-*",
    "priority": 10,
    "history_enabled": true,
    "history_ttl_seconds": 86400,
    "history_max_events": 1000,
    "cache_enabled": false,
    "max_members": 100,
    "max_event_size_bytes": 10240,
    "max_client_events_per_second": 10,
    "auth_endpoint": "https://your-app.com/channel-auth",
    "webhook_url": "https://your-app.com/channel-webhooks"
  }'
```

## Lifecycle Webhooks

Configure a `webhook_url` on your namespace or application to receive lifecycle events:

| Event | Trigger |
|-------|---------|
| `channel:occupied` | First subscriber joins a channel |
| `channel:vacated` | Last subscriber leaves a channel |
| `member:added` | User joins a presence channel |
| `member:removed` | User leaves a presence channel |

Webhooks are signed with your tenant's signing secret using HMAC-SHA256.

## Connection Management

### Connection Limits

Configure `max_connections_per_app` to limit concurrent WebSocket connections per application.

### Disconnect Users

Force-disconnect a user's connections:

```bash
curl -X DELETE "http://localhost:4000/v1/channels/users/{user_id}/connections" \
  -H "Authorization: Bearer <api_key>"
```

## Message Relay Integration

When delivering messages via the relay, include a `Ricqchet-Channel` header to automatically broadcast the delivery to a channel:

```bash
curl -X POST "http://localhost:4000/v1/publish" \
  -H "Authorization: Bearer <api_key>" \
  -H "Ricqchet-Destination: https://api.example.com/webhook" \
  -H "Ricqchet-Forward-Ricqchet-Channel: chat-room" \
  -d '{"event": "order.created"}'
```

On successful delivery, a `relay:message` event is broadcast to the specified channel.
