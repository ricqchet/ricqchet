# @ricqchet/client

TypeScript client for [Ricqchet](https://github.com/ricqchet/ricqchet), a self-hosted HTTP message queue service.

This client speaks Ricqchet's **relay API** — publishing messages, managing
deliveries, triggering real-time channel events, and verifying webhooks — using
an application API key. (Account, application, and API-key administration live
behind Ricqchet's separate JWT management API and the web dashboard.)

## Installation

```bash
npm install @ricqchet/client
```

## Quick Start

```typescript
import { RicqchetClient } from "@ricqchet/client";

const client = new RicqchetClient({
  // The base URL of your self-hosted Ricqchet instance
  baseUrl: "https://ricqchet.your-company.com", // or http://localhost:4000 in dev
  apiKey: process.env.RICQCHET_API_KEY!,
});

// Publish a message
const { messageId } = await client.publish(
  "https://myapp.com/webhook",
  { event: "order.created", id: 123 }
);
```

### Getting an API key

Ricqchet is self-hosted and single-organization — there is no public sign-up.
Sign in to your instance as an admin (or `member`), create an **Application**,
then create an **API key** for it from the dashboard or the management API. The
full secret is shown **only once** at creation — store it securely (e.g. a
secrets manager or `RICQCHET_API_KEY`).

Keys carry a **scope**: `relay` (the default — the full server-side key used by
this client) or `subscribe` (a **browser-safe** key that can _only_ open the
realtime channels WebSocket and is rejected on every REST endpoint). Use a
`relay` key here on the server; use a `subscribe` key for browser realtime (see
[Real-Time Channels](#real-time-channels-browser)). See the server's
[Authentication guide](https://github.com/ricqchet/ricqchet/blob/main/ricqchet-web/docs/authentication.md)
for details.

## Health Check

```typescript
// Public endpoint — no API key required. Handy for readiness probes.
const { status } = await client.health(); // { status: "ok" }
```

## Publishing Messages

### Simple Publish

```typescript
const { messageId } = await client.publish(
  "https://api.example.com/webhook",
  { event: "user.created", userId: 42 }
);
```

### With Options

```typescript
const { messageId } = await client.publish(
  "https://api.example.com/webhook",
  { event: "reminder" },
  {
    delay: "5m",              // Delay delivery
    dedupKey: "reminder-123", // Deduplication
    dedupTtl: 3600,           // Dedup TTL in seconds
    retries: 5,               // Max retry attempts
    forwardHeaders: {         // Headers to forward
      "x-custom-header": "value"
    }
  }
);
```

### Fan-Out (Multiple Destinations)

```typescript
const { messageIds } = await client.publishFanOut(
  [
    "https://service-a.example.com/webhook",
    "https://service-b.example.com/webhook",
  ],
  { event: "broadcast" }
);
```

Fan-out is limited to **100 destinations** per call (the client validates this
and throws a `validation_error` before sending). Fan-out cannot be combined with
batching.

### Batching

```typescript
// Messages with the same batch key are grouped
const { messageId } = await client.publish(
  "https://api.example.com/webhook",
  { event: "item.added" },
  {
    batchKey: "order-events",
    batchSize: 100,      // Max messages per batch
    batchTimeout: 30,    // Flush after 30 seconds
  }
);
```

## Message Management

### Get Message Status

```typescript
const message = await client.getMessage("550e8400-...");
console.log(message.status); // 'pending' | 'dispatched' | 'delivered' | 'failed'
console.log(message.attempts);
```

### Cancel a Message

```typescript
try {
  const { cancelled } = await client.cancelMessage("550e8400-...");
} catch (error) {
  if (error.type === "conflict") {
    console.log("Message already dispatched");
  }
}
```

## Channels (Real-Time Events)

Trigger and inspect real-time channel events server-side using your (`relay`)
API key. To **subscribe** from the browser, see
[Real-Time Channels](#real-time-channels-browser) below.

> The application's `channels_enabled` flag must be on, otherwise these calls
> reject with a `forbidden` (403) `RicqchetError`.

### Trigger an Event

```typescript
// Single channel
const { eventIds } = await client.triggerEvent({
  channel: "chat-room",
  event: "new-message",
  data: { text: "Hello!" },
  socketId: "123.456", // optional: exclude the originating socket
});

// Multiple channels (max 10 per call)
await client.triggerEvent({
  channels: ["room-1", "room-2"],
  event: "announcement",
  data: { text: "Hi everyone" },
});
```

### Trigger a Batch of Events

```typescript
// Up to 10 events; partial success is possible.
const { results } = await client.triggerBatchEvents({
  batch: [
    { channel: "chat", event: "msg", data: { text: "hi" } },
    { channel: "alerts", event: "ping" },
  ],
});

for (const r of results) {
  if (r.status === "error") console.warn(r.channel, r.error);
}
```

### Inspect Channels

```typescript
const channels = await client.listChannels();
const info = await client.getChannel("presence-lobby");
const history = await client.getChannelEvents("chat-room", { limit: 50 });
const members = await client.getChannelMembers("presence-lobby");
await client.disconnectUser("user-123");
```

## Real-Time Channels (Browser)

Subscribe to channels over a WebSocket from the browser. This is delivered as
optional subpath entry points so the core client stays dependency-free:

```bash
# the realtime client wraps the Phoenix channels protocol
npm install @ricqchet/client phoenix
# react is only needed for the hooks
```

> **Always use a `subscribe`-scoped key in the browser.** A subscribe key can
> _only_ open this WebSocket — it is rejected on every REST endpoint — so it is
> safe behind `NEXT_PUBLIC_`. Never ship a `relay` key to the browser. Mint one
> with `POST /v1/applications/:id/api-keys` `{ "scope": "subscribe" }`.

### Vanilla client — `@ricqchet/client/realtime`

```typescript
import { RicqchetRealtime } from "@ricqchet/client/realtime";

const rt = new RicqchetRealtime({
  url: "wss://ricqchet.your-company.com", // http(s)/ws(s); /channels is derived
  apiKey: process.env.NEXT_PUBLIC_RICQCHET_SUBSCRIBE_KEY!,
  userId: currentUser.id, // provisional — see auth below
  userInfo: { name: currentUser.name }, // presence metadata
});

// Subscribe by the BARE channel name — no application prefix (backend #127).
const channel = rt.subscribe("private-order-123");
channel.bind("order:updated", (data) => refetchOrder(data));

// Client-to-client events (private/presence only); resolves on server ack,
// rejects with a `rate_limited` RicqchetError if you exceed the per-connection cap.
await channel.trigger("client-typing", { at: Date.now() });

// Presence
const room = rt.subscribe("presence-lobby");
room.bindPresence({
  onSync: (members) => render(members),
  onJoin: (m) => console.log(`${m.userId} joined`),
  onLeave: (m) => console.log(`${m.userId} left`),
});

rt.unsubscribe("private-order-123");
rt.disconnect();
```

### React hooks — `@ricqchet/client/react`

Wrap your app in a provider (one shared connection), then subscribe per
component. The hooks replace hand-rolled `useEffect` + subscribe/bind/cleanup.

```tsx
import {
  RicqchetProvider,
  useRicqchetChannel,
  useRicqchetEvent,
  useRicqchetSubscribed,
  useRicqchetPresence,
} from "@ricqchet/client/react";

function Providers({ children }) {
  return (
    <RicqchetProvider
      url="wss://ricqchet.your-company.com"
      apiKey={process.env.NEXT_PUBLIC_RICQCHET_SUBSCRIBE_KEY!}
      userId={session.user.id}
    >
      {children}
    </RicqchetProvider>
  );
}

function OrderView({ orderId }: { orderId: string }) {
  const channel = useRicqchetChannel(`private-order-${orderId}`);
  const isConnected = useRicqchetSubscribed(channel);

  useRicqchetEvent(channel, "order:updated", () => {
    queryClient.invalidateQueries({ queryKey: ["order", orderId] });
  });

  return <ConnectionBadge online={isConnected} />;
}
```

`useRicqchetPresence(channel)` returns `{ members }` for `presence-` channels.
Pass `null` to `useRicqchetChannel` to skip subscribing (e.g. while an id loads).

### Authorizing private/presence channels — `@ricqchet/client/next`

Unlike Pusher, **the Ricqchet backend** calls _your_ auth endpoint server-to-server
on join (`POST { channel, user_id, socket_id }`) and trusts the HTTP status — you
do **not** sign a token. Configure your application's `channels_auth_endpoint` to
point at this route. Return verified identity to override the client-supplied
(untrusted) `user_id`/`user_info` for presence and client events (backend #129):

```typescript
// app/api/ricqchet/channel-auth/route.ts
import { createChannelAuthRoute } from "@ricqchet/client/next";

export const POST = createChannelAuthRoute(async ({ channel, userId, socketId }) => {
  const session = await getSession();
  if (!session || !canAccess(session, channel)) return false; // 403 deny
  // 200 allow + bind the authoritative identity:
  return { userId: session.user.id, userInfo: { name: session.user.name } };
  // (return `true` to allow without binding identity)
});
```

Because the backend sends the auth request unsigned, protect the route by
embedding a secret in the configured URL and passing `{ secret }`:

```typescript
export const POST = createChannelAuthRoute(authorize, {
  secret: process.env.RICQCHET_CHANNEL_AUTH_SECRET,
});
// configure channels_auth_endpoint as: https://app/api/ricqchet/channel-auth?secret=...
```

Ricqchet also delivers presence/occupancy **webhooks** (`channel:occupied`,
`member:added`, …) to your `channels_webhook_url`, signed with the same HMAC as
message webhooks:

```typescript
import { verifyChannelWebhookRequest } from "@ricqchet/client/next";

export async function POST(request: Request) {
  const result = await verifyChannelWebhookRequest(request, signingSecret);
  if (!result.valid) return new Response(result.error, { status: 401 });
  if (result.event.event === "member:added") track(result.event.userId);
  return new Response("ok");
}
```

## Webhook Verification

Verify incoming webhooks from Ricqchet using HMAC signatures.

### Get Signing Secret

```typescript
const signingSecret = await client.getSigningSecret();
```

### Verify Signature

```typescript
import { verifyRequest } from "@ricqchet/client";

// Express example
app.post("/webhook", express.raw({ type: "application/json" }), (req, res) => {
  const result = verifyRequest(req.headers, req.body, signingSecret);

  if (!result.valid) {
    return res.status(401).json({ error: result.error });
  }

  // Signature valid, process the webhook
  console.log("Message ID:", result.metadata.messageId);
  console.log("Attempt:", result.metadata.attempt);

  res.status(200).send("OK");
});
```

### Low-Level Verification

```typescript
import { verifySignature } from "@ricqchet/client";

const result = verifySignature(
  req.headers["x-ricqchet-signature"],
  rawBody,
  signingSecret,
  { maxAge: 300 } // Reject signatures older than 5 minutes
);

if (result.valid) {
  console.log("Timestamp:", result.metadata.timestamp);
}
```

## Error Handling

```typescript
import { RicqchetError } from "@ricqchet/client";

try {
  await client.publish("invalid-url", { event: "test" });
} catch (error) {
  if (error instanceof RicqchetError) {
    switch (error.type) {
      case "validation_error":
        console.log("Invalid request:", error.message);
        break;
      case "unauthorized":
        console.log("Check your API key");
        break;
      case "rate_limited":
        console.log("Slow down!");
        break;
      default:
        console.log("Error:", error.message);
    }
  }
}
```

## Configuration Options

### Client Options

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `baseUrl` | string | yes | Ricqchet server URL |
| `apiKey` | string | yes | API key for authentication |
| `timeout` | number | no | HTTP timeout in ms (default: 30000) |

### Publish Options

| Option | Type | Description |
|--------|------|-------------|
| `delay` | string | Delay delivery (e.g., "30s", "5m", "1h") |
| `dedupKey` | string | Deduplication key |
| `dedupTtl` | number | Deduplication TTL in seconds |
| `retries` | number | Max retry attempts |
| `batchKey` | string | Batch key for grouping |
| `batchSize` | number | Max batch size (1-1000) |
| `batchTimeout` | number | Batch timeout in seconds |
| `forwardHeaders` | Record<string, string> | Headers to forward |
| `contentType` | string | Content-Type header |

## License

MIT
