# @ricqchet/client

TypeScript client for [Ricqchet](https://github.com/doomspork/ricqchet) HTTP message queue service.

## Installation

```bash
npm install @ricqchet/client
```

## Quick Start

```typescript
import { RicqchetClient } from "@ricqchet/client";

const client = new RicqchetClient({
  baseUrl: "https://your-ricqchet.fly.dev",
  apiKey: process.env.RICQCHET_API_KEY!,
});

// Publish a message
const { messageId } = await client.publish(
  "https://myapp.com/webhook",
  { event: "order.created", id: 123 }
);
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
