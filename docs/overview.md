# Overview

Ricqchet is an HTTP message relay that sits between your application and destination endpoints. Instead of making HTTP requests directly, you publish messages to Ricqchet, which handles delivery with automatic retries, scheduling, and tracking.

## Why Use a Message Relay?

### Reliable Delivery

Direct HTTP calls fail. Networks drop, services restart, endpoints time out. Ricqchet queues your messages and retries with exponential backoff until delivery succeeds or retries are exhausted. Your application can fire-and-forget without implementing retry logic.

### Decoupling

Your application doesn't need to wait for downstream services. Publish a message and move on. This is especially valuable for:

- Webhook delivery to third-party services
- Event notifications that shouldn't block your main flow
- Communication with unreliable or slow endpoints

### Observability

Every message has a trackable ID. You can check delivery status, see attempt counts, view response codes, and debug failed deliveries through the API.

## Core Concepts

### Messages

A message is an HTTP request that Ricqchet delivers on your behalf. It includes:

- **Destination URL**: Where to send the request
- **Payload**: The request body (typically JSON)
- **Headers**: Any headers to forward to the destination

### Delivery Lifecycle

```
publish → pending → dispatched → delivered
                              ↘ failed (after retries exhausted)
```

1. **Publish**: Your application POSTs to Ricqchet
2. **Pending**: Message queued, waiting for dispatch
3. **Dispatched**: Actively being delivered
4. **Delivered**: Destination returned 2xx
5. **Failed**: All retry attempts exhausted

### Retries

When delivery fails, Ricqchet waits and tries again with increasing delays:

| Attempt | Wait Time |
|---------|-----------|
| 1 | 10 seconds |
| 2 | 30 seconds |
| 3 | 90 seconds |
| 4+ | Continues growing (max 8 hours) |

The default is 3 retries. You can customize this per-message or disable retries entirely for fire-and-forget delivery.

## Feature Summary

### Header Forwarding

Pass custom headers to your destination endpoint. Useful for:

- **Correlation IDs**: Track requests across services
- **Authentication**: Forward tokens or signatures to the destination
- **Metadata**: Pass context like source service, request type, or tenant info

Any header prefixed with `Ricqchet-Forward-` is forwarded with the prefix stripped. For example, `Ricqchet-Forward-X-Correlation-Id: abc123` arrives at the destination as `X-Correlation-Id: abc123`.

### Fan-out

Broadcast one message to multiple destinations with a single API call. Each destination gets its own message with independent delivery tracking. Use this for:

- Notifying multiple services about the same event
- Multi-region delivery
- Redundant webhook delivery

### Deduplication

Prevent duplicate message processing by providing a deduplication key. If you publish the same key twice within the TTL window, the second request is rejected. Use this for:

- Protecting against double-submits
- Ensuring idempotent event publishing
- Retry-safe client implementations

### Delayed Delivery

Schedule messages for future delivery. Useful for:

- Reminder notifications
- Scheduled jobs triggered via webhook
- Rate limiting by spreading requests over time
- Implementing "send later" functionality

### Batching

Group multiple messages into a single HTTP delivery. Instead of 100 separate webhooks, your destination receives one request with an array of payloads. Use this for:

- Reducing load on destination endpoints
- Aggregating events before processing
- Cost optimization when destination charges per request

## What Ricqchet Adds to Your Requests

When delivering a message, Ricqchet includes these headers:

| Header | Purpose |
|--------|---------|
| `X-Ricqchet-Message-Id` | Unique message identifier for tracking |
| `X-Ricqchet-Attempt` | Current attempt number (1, 2, 3...) |
| `User-Agent: Ricqchet/1.0` | Identifies Ricqchet as the sender |

Your forwarded headers are included alongside these.

## Security

- API keys are hashed with Argon2 before storage
- Each API key is scoped to an application within a tenant
- Destination URLs are validated before acceptance
- Certain headers (Host, Connection, etc.) cannot be forwarded for security

## Next Steps

- [API Reference](api-reference.md) - Full endpoint documentation
- [Delivery](delivery.md) - Retry behavior and timeout details
- [Batching](batching.md) - Grouping messages for bulk delivery
- [Receiving Webhooks](receiving-webhooks.md) - Guide for destination endpoints
