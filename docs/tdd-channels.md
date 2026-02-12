# 20260212 WebSocket Channels

## Introduction

Ricqchet currently provides HTTP message relay with guaranteed delivery, retries, fan-out, batching, and scheduling. We want to expand into real-time WebSocket messaging (a la Pusher Channels) to serve serverless applications that need to push live UI updates. The pattern: a serverless function sends an event to Ricqchet via REST API, Ricqchet broadcasts it to connected browser clients over WebSocket. Phoenix's built-in Channels, Presence, and PubSub make this a natural extension of the platform with zero new dependencies.

## Resources

- [Product plan](/docs/tdd-channels.md)
- GitHub issues: [#99](https://github.com/doomspork/ricqchet/issues/99)–[#118](https://github.com/doomspork/ricqchet/issues/118) (epic:channels)
- [Pusher Channels docs](https://pusher.com/docs/channels/)
- [Phoenix Channels guide](https://hexdocs.pm/phoenix/channels.html)
- [Phoenix Presence guide](https://hexdocs.pm/phoenix/Phoenix.Presence.html)

## Glossary

- **Channel**: A named topic that clients subscribe to over WebSocket to receive real-time events. Channels are ephemeral — they exist in memory when they have subscribers and disappear when they do not.
- **Namespace**: An application-level configuration pattern that applies rules (history, cache, limits, auth) to channels matching a name pattern (e.g., `private-chat-*`).
- **Presence**: Automatic tracking of which users are subscribed to a channel, with join/leave events and arbitrary user metadata. Built on Phoenix Presence CRDTs.
- **Client event**: An event sent directly from a connected WebSocket client to other subscribers on the same channel (peer-to-peer), prefixed with `client-`.
- **Cache channel**: A channel where the last published event is cached and delivered to new subscribers immediately on join.
- **Event recovery**: Automatic replay of missed events when a client reconnects, using a `last_event_id` to determine what was missed.

## Current State

Ricqchet provides HTTP message relay only. Messages are published via REST API, stored in PostgreSQL, and delivered to destination URLs via Oban workers with retry logic. The platform supports:

- Single message delivery with configurable retries and exponential backoff
- Fan-out to up to 100 destination URLs
- Batching with configurable batch size and timeout
- Scheduled delivery with delays
- Message deduplication
- Per-destination flow control (parallelism and rate limiting)
- Dead letter queue with webhook notifications
- Real-time activity events via Phoenix PubSub (internal dashboard only)

There is an existing WebSocket endpoint (`/socket`) used for the internal dashboard, authenticated via JWT. It broadcasts message lifecycle events (created, dispatched, delivered, failed) to dashboard users.

## Future State

Ricqchet will offer a public-facing WebSocket endpoint (`/channels`) where end-users of Ricqchet's customers can subscribe to named channels and receive real-time events. Key differences from the current state:

- **New audience**: WebSocket clients are end-users of Ricqchet customers (not dashboard users), authenticated via API key rather than JWT.
- **New data flow**: Server-to-client push via WebSocket, triggered by REST API calls from the customer's backend. This is the inverse of the current model where Ricqchet pushes to customer HTTP endpoints.
- **Ephemeral channels**: Channels exist only in memory (PubSub topics), unlike messages which are always persisted. History persistence is opt-in via namespace configuration.
- **Client-to-client communication**: Private and presence channels support client events, enabling peer-to-peer messaging without a server roundtrip.
- **Presence tracking**: Automatic "who's online" functionality with member lists and join/leave events, powered by Phoenix Presence CRDTs. Supports 1,000+ members per channel (vs Pusher's 100-member hard cap).
- **Message recovery**: Configurable event history with automatic replay on reconnect, addressing Pusher's biggest weakness (no recovery for missed messages).

The REST API publish flow integrates with existing infrastructure: API key auth, multi-tenancy, and rate limiting are reused from the message relay product.

## Not in Scope

- **Pusher Protocol compatibility**: We are building a custom protocol optimized for Phoenix. A Pusher-compatible adapter layer could be added in the future but is not planned.
- **End-to-end encryption**: Encrypted channels (like Pusher's `private-encrypted-` prefix) are not included in the initial scope.
- **Database CDC (Change Data Capture)**: Streaming database changes to channels (like Supabase Realtime) is not planned.
- **Push notifications**: Routing channel events to APNs/FCM for mobile push is not in scope.
- **Client SDKs**: Custom JavaScript/mobile SDKs are deferred. Initial launch will document how to connect using standard Phoenix channel clients.
- **Cross-region replication**: Multi-node PubSub (Phase 5) covers single-region clustering. Cross-region/global distribution is out of scope.
- **Per-message billing/metering**: Usage tracking for billing purposes is not included in the initial implementation.

## Technical Design

### Summary

The channels feature adds a new `ChannelSocket` WebSocket endpoint at `/channels` with API key authentication, a `PubsubChannel` Phoenix Channel module handling public/private/presence channel types, and a REST API under `/v1/channels/` for server-side event publishing. Events are broadcast via Phoenix PubSub with optional PostgreSQL persistence for history and recovery. Presence is implemented using Phoenix Presence CRDTs. Channel lifecycle webhooks reuse the existing Oban-based HTTP delivery infrastructure. Multi-tenant isolation is enforced through PubSub topic namespacing (`channels:app:<application_id>:<channel_name>`) and socket-level application ID verification.

The approach chosen is a custom protocol (not Pusher-compatible) to fully leverage Phoenix's strengths: native Channel multiplexing, heartbeat-based connection health, CRDT-based Presence, and the existing PubSub infrastructure. This was chosen over Pusher Protocol compatibility (like Soketi) because it removes constraints like the 100-member presence limit baked into the Pusher protocol spec and allows us to offer features like configurable message history that don't fit the Pusher model.

### ERD

#### New tables

```
┌─────────────────────────┐       ┌─────────────────────────┐
│    channel_namespaces   │       │     channel_events      │
├─────────────────────────┤       ├─────────────────────────┤
│ id            binary_id │       │ id            binary_id │
│ application_id      FK  │──┐    │ application_id      FK  │──┐
│ tenant_id           FK  │  │    │ tenant_id           FK  │  │
│ pattern         string  │  │    │ channel          string │  │
│ priority       integer  │  │    │ event_name       string │  │
│ history_enabled boolean │  │    │ data             binary │  │
│ history_ttl_seconds int │  │    │ data_size_bytes     int │  │
│ history_max_events  int │  │    │ user_id          string │  │
│ cache_enabled   boolean │  │    │ socket_id        string │  │
│ max_members     integer │  │    │ sequence      bigserial │  │
│ max_event_size_bytes    │  │    │ inserted_at   datetime  │  │
│   integer               │  │    └─────────────────────────┘  │
│ max_client_events_per   │  │                                 │
│   _second       integer │  │    ┌─────────────────────────┐  │
│ auth_endpoint    string │  │    │     applications        │  │
│ webhook_url      string │  │    │ (existing, altered)     │  │
│ inserted_at   datetime  │  │    ├─────────────────────────┤  │
│ updated_at    datetime  │  ├───>│ id            binary_id │<─┘
└─────────────────────────┘       │ ...existing fields...   │
                                  │ channels_enabled  bool  │
                                  │ channels_auth_endpoint  │
                                  │   string                │
                                  │ channels_webhook_url    │
                                  │   string                │
                                  └─────────────────────────┘
```

#### Indexes

- `channel_namespaces`: unique on `(application_id, pattern)`, index on `(tenant_id)`
- `channel_events`: index on `(application_id, channel, sequence)`, index on `(tenant_id, inserted_at)`

## Release Plan

The feature is released in 5 phases. Each phase is independently deployable and adds incremental value.

1. **Phase 1 — MVP (public channels + server publishing)**: Database migrations, ChannelSocket with API key auth, PubsubChannel for public channels, REST API for publishing events and querying channels. This is the minimum viable product: a serverless app can publish events via REST API and browser clients receive them over WebSocket.

2. **Phase 2 — Private channels + history**: Channel authorization (calling customer's auth endpoint for private/presence channels), event history persistence in PostgreSQL, history query API, missed-message recovery on reconnect, and namespace configuration CRUD.

3. **Phase 3 — Presence**: Phoenix Presence module for member tracking, presence_state and presence_diff system events, member list in channel info API, presence webhooks.

4. **Phase 4 — Advanced features**: Batch event publishing, client events (peer-to-peer), cache channels, history cleanup worker, channel lifecycle webhooks, telemetry metrics, rate limiting and size enforcement.

5. **Phase 5 — Polish**: OpenApiSpex schemas and documentation, multi-node PubSub support (PG2 adapter), connection management and limits, terminate user API, message relay to channels integration.

Migration strategy:
- All migrations are additive (new tables + new columns with defaults) — no destructive changes
- Feature is gated behind `channels_enabled` boolean on the application
- No impact on existing message relay functionality

## Monitoring/Telemetry

### Mandatory

- **Channel events published per second**: counter by application_id and channel_type — core throughput metric
- **Active WebSocket connections**: gauge by application_id — capacity planning and limit enforcement
- **Channel joins/leaves per second**: counter by channel_type — subscription activity
- **Auth endpoint latency**: summary/histogram — customer auth endpoint performance directly affects join latency
- **Auth endpoint failures**: counter by error type — detect customer auth endpoint outages
- **Event recovery count**: counter of events replayed on reconnect — indicates disconnect frequency and history usage
- **Channel events table size**: gauge by tenant_id — storage growth monitoring for cleanup worker tuning

### Nice to have

- **Presence member count per channel**: last_value gauge — high-cardinality but useful for large presence channels
- **Client events per second**: counter — peer-to-peer messaging volume
- **Webhook delivery latency**: summary — lifecycle webhook performance
- **Cache hit rate**: counter of cached events served vs total joins — cache channel effectiveness
- **History cleanup events deleted**: counter per cleanup run — verify cleanup worker is keeping up

## Testing

### Use Cases

- Connect to WebSocket with valid API key and subscribe to a public channel
- Publish an event via REST API and verify WebSocket subscribers receive it
- Subscribe to a private channel with valid authorization
- Attempt to subscribe to a private channel without authorization (expect rejection)
- Subscribe to a presence channel and verify member list and join/leave events
- Disconnect, miss events, reconnect with last_event_id, verify missed events are replayed
- Reconnect with an expired last_event_id (pruned from history), verify recovery_failed event
- Send a client event on a private channel and verify other subscribers receive it
- Exceed client event rate limit and verify error response without disconnect
- Subscribe to a cache channel and verify the last event is delivered immediately
- Publish events exceeding max_event_size_bytes and verify rejection
- Verify tenant isolation: application A cannot subscribe to application B's channels
- Force disconnect a user via terminate API and verify all their connections are closed
- Verify channel:occupied webhook fires on first subscriber, channel:vacated on last leave

### Testing Notes

- Use `Phoenix.ChannelTest` for channel unit tests — it provides `socket/3`, `subscribe_and_join/3`, and assertion helpers
- Use `Bypass` for mocking customer auth endpoints (consistent with existing test patterns)
- Use `Mox` for mocking the HTTP client in auth module tests
- Test Oban workers (cleanup, webhooks) using `Oban.Testing` helpers
- Presence tests need careful handling of async CRDT syncs — use `assert_push` with timeouts
- Multi-tenant isolation tests should create two separate applications and verify cross-tenant access is denied at every layer (socket connect, channel join, API queries)
- Load testing at startup-scale targets (1K connections, 100 channels) should be done manually with a tool like `k6` or `artillery` before Phase 5 launch

## Steps to Completion

### jakarta-v2 (this repo)

**Phase 1 — MVP** (issues #99–#103)
- [ ] Create database migrations: `channel_events`, `channel_namespaces`, alter `applications` (#99)
- [ ] Create `ChannelEvent` and `Namespace` Ecto schemas (#99)
- [ ] Create `ChannelSocket` with API key auth, register at `/channels` in endpoint.ex (#100)
- [ ] Create `PubsubChannel` for public channel subscriptions (#101)
- [ ] Create `EventPublisher` with PubSub broadcast (#102)
- [ ] Create `ChannelController` with `POST /v1/channels/events` (#102)
- [ ] Create `Channels` context facade module (#102)
- [ ] Create `SubscriberTracker` GenServer with ETS counters (#103)
- [ ] Create `GET /v1/channels` and `GET /v1/channels/:channel_name` endpoints (#103)
- [ ] Add routes to `router.ex` and `SubscriberTracker` to supervision tree (#103)

**Phase 2 — Private channels + history** (issues #104–#107)
- [ ] Create `Channels.Auth` module for customer auth endpoint calls (#104)
- [ ] Add private channel authorization to `PubsubChannel` join (#104)
- [ ] Add event persistence to `EventPublisher` (conditional on namespace config) (#105)
- [ ] Create `History` module for event queries (#106)
- [ ] Create `GET /v1/channels/:channel_name/events` endpoint (#106)
- [ ] Add missed-message recovery to `PubsubChannel` join (last_event_id) (#106)
- [ ] Create `NamespaceConfig` module with pattern matching and ETS cache (#107)
- [ ] Create `ChannelNamespaceController` with CRUD endpoints (#107)

**Phase 3 — Presence** (issue #108)
- [ ] Create `RicqchetWeb.Channels.Presence` module (#108)
- [ ] Add presence tracking to `PubsubChannel` for `presence-*` channels (#108)
- [ ] Add member list to `GET /v1/channels/:channel_name` for presence channels (#108)

**Phase 4 — Advanced features** (issues #109–#114)
- [ ] Add `POST /v1/channels/events/batch` endpoint (#109)
- [ ] Add client event handling (`client-*` prefix) to `PubsubChannel` (#110)
- [ ] Add cache channel support (last event on subscribe) (#111)
- [ ] Create `CleanupWorker` Oban cron job for history TTL enforcement (#112)
- [ ] Create `WebhookNotifier` Oban worker for lifecycle/presence webhooks (#113)
- [ ] Add telemetry events and metric definitions (#114)
- [ ] Add event size enforcement and client event rate limiting (#114)

**Phase 5 — Polish** (issues #115–#118)
- [ ] Add OpenApiSpex schemas for all channel endpoints (#115)
- [ ] Write `docs/channels.md` and update existing docs (#115)
- [ ] Configure PG2 PubSub adapter for multi-node support (#116)
- [ ] Add per-application connection and channel limits (#117)
- [ ] Add terminate user API (`DELETE /v1/channels/users/:user_id/connections`) (#117)
- [ ] Add message relay to channels integration (#118)

### Other

- [ ] Manual load testing with k6 or artillery at 1K connections / 100 channels before Phase 5 signoff
- [ ] Update deployment configuration for new Oban queues (`channel_webhooks`) and cron schedule

## Open Questions

- ~~Should we target Pusher Protocol compatibility?~~ **Decided: No.** Custom protocol to maximize Phoenix strengths.
- ~~What level of message history?~~ **Decided: Full configurable history** with TTL and max size per channel.
- ~~Separate API endpoints or integrated with message relay?~~ **Decided: New dedicated endpoints** under `/v1/channels/`.
- ~~Target scale?~~ **Decided: Startup-scale** (~1K concurrent connections per tenant, ~100 channels).
- Should channel broadcast in the relay integration (Phase 5) happen before or after successful HTTP delivery? Needs design decision before Phase 5 work begins.
- Should we offer scoped/read-only API keys for WebSocket connections (vs reusing full API keys)? This would improve security for client-side key exposure. Consider for Phase 5 or post-launch.
- What is the maximum `history_ttl_seconds` we should allow? Unbounded TTL could lead to storage issues. Consider setting a platform-wide ceiling (e.g., 7 days) that can be raised for enterprise tenants.
