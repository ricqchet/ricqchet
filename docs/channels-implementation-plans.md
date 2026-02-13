# Channels Phase 4 & 5: Implementation Plans

Implementation plans for the remaining 10 `epic:channels` GitHub issues. Each plan references existing codebase patterns and provides file-level implementation details.

## Issue Index

### Phase 4 — Advanced Features (P1)

| Issue | Title | Complexity | Key Files |
|-------|-------|-----------|-----------|
| [#109](#109-batch-event-publishing) | Batch event publishing | Medium | ChannelController, router |
| [#110](#110-client-events) | Client events (peer-to-peer) | Medium | PubsubChannel, new rate limiter |
| [#111](#111-cache-channels) | Cache channels | Low | PubsubChannel, Channels context |
| [#112](#112-history-cleanup-worker) | History cleanup worker | Medium | New CleanupWorker, config |
| [#113](#113-lifecycle-webhooks) | Lifecycle and presence webhooks | High | New WebhookNotifier, PubsubChannel |
| [#114](#114-telemetry-and-metrics) | Telemetry and metrics | Medium | EventPublisher, PubsubChannel, telemetry.ex |

### Phase 5 — Polish (P2)

| Issue | Title | Complexity | Key Files |
|-------|-------|-----------|-----------|
| [#115](#115-openapispex-and-documentation) | OpenApiSpex schemas and docs | High (volume) | New schemas, controllers, docs/ |
| [#116](#116-multi-node-pubsub) | Multi-node pubsub support | Low | SubscriberTracker, Channels context |
| [#117](#117-connection-management) | Connection management and limits | Medium | New ConnectionTracker, ChannelSocket, router |
| [#118](#118-relay-integration) | Message relay integration | Low | Delivery.Worker |

### Recommended Implementation Order

1. #112 — Cleanup worker (standalone, no deps)
2. #109 — Batch events (new route + controller action)
3. #111 — Cache channels (small PubsubChannel change)
4. #110 — Client events (PubsubChannel + new GenServer)
5. #113 — Lifecycle webhooks (new Oban worker + PubsubChannel hooks)
6. #114 — Telemetry (instrument all modules)
7. #116 — Multi-node (SubscriberTracker cluster functions)
8. #117 — Connection limits (new GenServer + controller)
9. #118 — Relay integration (Delivery.Worker change)
10. #115 — Docs (document everything above)

---

## #109: Batch Event Publishing

### Goal
`POST /v1/channels/events/batch` — publish up to 10 events in one request.

### Changes

**`lib/ricqchet_web/controllers/channel_controller.ex`** — Add `batch_create/2`:
- Accept `%{"batch" => events}` where events is a list of maps
- Validate batch size (max 10, non-empty)
- Publish each event independently via `Channels.publish_event/5`
- Each event gets its own validation and status (partial success possible)
- Return 202 with per-event results

**`lib/ricqchet_web/controllers/channel_json.ex`** — Add batch response render:
```
render("batch_created.json", %{results: results}) → %{results: results}
```

**`lib/ricqchet_web/router.ex`** — Add route:
```
post "/channels/events/batch", ChannelController, :batch_create
```

### API

Request:
```json
{"batch": [
  {"channel": "chat-1", "event": "msg", "data": {"text": "hi"}, "socket_id": "optional"},
  {"channel": "chat-2", "event": "msg", "data": {"text": "hello"}}
]}
```

Response (202):
```json
{"results": [
  {"channel": "chat-1", "event": "msg", "event_id": "uuid", "status": "ok"},
  {"channel": "chat-2", "event": "msg", "event_id": "uuid", "status": "ok"}
]}
```

### Tests (`test/ricqchet_web/controllers/channel_controller_test.exs`)
- Batch with 2-3 events to different channels
- Batch limit exceeded (>10 → 422)
- Empty batch (422)
- Partial failure (one invalid channel name)
- Missing required fields per event
- Channels not enabled (403)

---

## #110: Client Events

### Goal
Allow clients on private/presence channels to send `client-` prefixed events to peers with rate limiting.

### New File

**`lib/ricqchet/channels/client_event_rate_limiter.ex`** — GenServer + ETS:
- ETS key: `{application_id, user_id, window_second}`
- `check_rate(app_id, user_id, limit)` → `:ok | :rate_limited`
- Atomic `update_counter` per second window
- Periodic cleanup of stale entries (every 5s)
- Default limit: 10/second, configurable per namespace via `max_client_events_per_second`

### Changes

**`lib/ricqchet_web/channels/pubsub_channel.ex`**:
- Add `handle_in("client-" <> _ = event, payload, socket)`:
  - Validate: channel is private or presence (reject on public)
  - Check rate limit via `ClientEventRateLimiter.check_rate/3`
  - `broadcast_from!(socket, event, msg)` — excludes sender
  - Include `user_id` in broadcast payload
- Modify `do_join/4`: store `channel_name` in socket assigns

**`lib/ricqchet/application.ex`** — Add `ClientEventRateLimiter` to children.

### Tests (`test/ricqchet_web/channels/pubsub_channel_test.exs`)
- Client event on private channel (success)
- Client event on public channel (rejected)
- Rate limiting (exceed, verify error reply not disconnect)
- Sender exclusion (sender doesn't receive own event)
- Payload includes sender's `user_id`

---

## #111: Cache Channels

### Goal
Push the latest event to new subscribers when namespace has `cache_enabled: true`.

### Changes

**`lib/ricqchet/channels/channels.ex`** — Add:
```elixir
def get_last_event(application_id, channel_name) do
  History.get_recent_events(application_id, channel_name, limit: 1)
  |> List.first()
end
```

**`lib/ricqchet_web/channels/pubsub_channel.ex`**:
- In `do_join/4`: when no `last_event_id`, send `{:maybe_send_cached_event, app_id, channel_name}`
- Add `handle_info({:maybe_send_cached_event, ...})`:
  - Check namespace `cache_enabled: true`
  - Query last event via `Channels.get_last_event/2`
  - Push as `ricqchet:cached_event` system event

### Design Notes
- Recovery (`last_event_id`) takes priority over cache
- Cache requires `history_enabled` (reads from `channel_events` table)
- No cached event when no events exist

### Tests (`test/ricqchet_web/channels/pubsub_channel_test.exs`)
- Subscriber receives cached event when enabled + events exist
- No cached event when disabled / no events
- Recovery takes priority over cache
- Cached event is the most recent one

---

## #112: History Cleanup Worker

### Goal
Oban cron worker to clean expired channel events by TTL and max event limits.

### New File

**`lib/ricqchet/channels/cleanup_worker.ex`**:
- `use Oban.Worker, queue: :default, max_attempts: 1`
- `perform/1`:
  1. Query namespaces with `history_enabled: true` AND (`history_ttl_seconds` or `history_max_events` set)
  2. For each: `cleanup_by_ttl/1` + `cleanup_by_max_events/1`
  3. Log stats
- TTL: `DELETE WHERE application_id = ? AND inserted_at < (now - ttl)`, batch 1000
- Max events: per-channel trim using existing `offset + subquery` pattern from EventPublisher
- Pattern matching: reuse `Namespaces.pattern_matches?/2` logic

### Config Change

**`config/config.exs`** — Add Oban cron:
```elixir
plugins: [
  Oban.Plugins.Pruner,
  {Oban.Plugins.Cron, crontab: [
    {"*/15 * * * *", Ricqchet.Channels.CleanupWorker}
  ]}
]
```

### Tests (`test/ricqchet/channels/cleanup_worker_test.exs`)
- TTL cleanup deletes old events
- Max events trims excess per channel
- Respects per-namespace settings
- No-op when no cleanup config exists
- Batch deletion for large datasets
- Pattern matching filters channels correctly

---

## #113: Lifecycle Webhooks

### Goal
Webhook notifications for `channel:occupied`, `channel:vacated`, `member:added`, `member:removed`.

### New File

**`lib/ricqchet/channels/webhook_notifier.ex`**:
- `use Oban.Worker, queue: :channel_webhooks, max_attempts: 3`
- `enqueue/2` — convenience for `__MODULE__.new(args) |> Oban.insert()`
- `perform/1`:
  1. Resolve webhook URL: namespace `webhook_url` → application `channels_webhook_url`
  2. Build event payload
  3. Sign with HMAC-SHA256 (reuse `Delivery.Signer`)
  4. POST via Req with SSRF protection
- No-op when no webhook URL configured

### Config Change

**`config/config.exs`** — Add queue:
```
queues: [default: 5, delivery: 50, dlq_notifications: 10, channel_webhooks: 5]
```

### Changes

**`lib/ricqchet_web/channels/pubsub_channel.ex`**:
- `do_join/4`: on `SubscriberTracker.track_join` → `:first_subscriber`, enqueue `channel:occupied`
- `terminate/2`: on `track_leave` → `:last_subscriber`, enqueue `channel:vacated`
- `handle_info(:after_join_presence)`: enqueue `member:added`
- `terminate/2` for presence channels: enqueue `member:removed`

### Webhook Payload
```json
{
  "event": "channel:occupied",
  "channel": "chat-room1",
  "application_id": "uuid",
  "timestamp": "2026-02-13T...",
  "user_id": "alice",       // member events only
  "user_info": {}            // member events only
}
```

### Tests (`test/ricqchet/channels/webhook_notifier_test.exs`)
- Occupied/vacated on first join / last leave
- Member added/removed for presence
- URL resolution (namespace → app fallback)
- No-op when no URL configured
- Retry on failure (3 attempts)
- Signed payload headers

---

## #114: Telemetry and Metrics

### Goal
Instrument channels with telemetry events and add metric definitions.

### Telemetry Events

| Event | Emitter | Measurements | Metadata |
|-------|---------|-------------|----------|
| `channels.event.published` | EventPublisher | `{count: 1}` | `{channel, application_id}` |
| `channels.connection.opened` | ChannelSocket | `{count: 1}` | `{application_id}` |
| `channels.connection.closed` | PubsubChannel terminate | `{count: 1}` | `{application_id}` |
| `channels.join` | PubsubChannel do_join | `{count: 1}` | `{channel_type, application_id}` |
| `channels.presence.track` | PubsubChannel after_join | `{count: 1}` | `{channel, member_count}` |
| `channels.auth.complete` | PubsubChannel join_with_auth | `{duration}` | `{result, channel}` |
| `channels.recovery` | PubsubChannel recover_events | `{events_replayed}` | `{channel, application_id}` |

### Changes

**`lib/ricqchet/channels/event_publisher.ex`**:
- Emit `event.published` after broadcast
- Add `check_event_size/3` using `max_event_size_bytes` from namespace
- Return `{:error, :event_too_large}` if exceeded

**`lib/ricqchet_web/channels/channel_socket.ex`**:
- Emit `connection.opened` on successful connect

**`lib/ricqchet_web/channels/pubsub_channel.ex`**:
- Emit `join`, `connection.closed`, `presence.track`, `auth.complete`, `recovery`

**`lib/ricqchet_web/telemetry.ex`** — Add metric definitions:
- Counters for events published, connections, joins, presence tracks
- Summary for auth duration
- Sum for recovery events replayed

### Tests (`test/ricqchet/channels/telemetry_test.exs`)
- Attach handlers, verify each event fires correctly
- Event size enforcement (oversized → error)

---

## #115: OpenApiSpex and Documentation

### Goal
Add OpenApiSpex schemas and user-facing docs for all channel endpoints.

### New Files (`lib/ricqchet_web/schemas/channels/`)

9 schema files following existing pattern (`use RicqchetWeb.Schema` + `OpenApiSpex.schema(%{...})`):

1. `trigger_event_request.ex`
2. `trigger_event_response.ex`
3. `batch_trigger_request.ex`
4. `batch_trigger_response.ex`
5. `channel_info.ex`
6. `channel_list.ex`
7. `channel_event_history.ex`
8. `namespace_params.ex`
9. `namespace_response.ex`

### Controller Changes
Add `operation/2` to: `ChannelController`, `ChannelEventController`, `ChannelMembersController`, `ChannelNamespaceController`

### Documentation
- **New:** `docs/channels.md` — comprehensive guide
- **Update:** `docs/api-reference.md`, `docs/authentication.md`, `docs/overview.md`, `README.md`

### Dependencies
Should be done after all other features are complete to document final API.

---

## #116: Multi-Node PubSub

### Goal
Cluster-aware subscriber tracking for multi-node deployments.

### Key Insight
Phoenix.PubSub 2.0+ uses `:pg` by default — already distributes. dns_cluster is configured. **No adapter change needed.**

### Changes

**`lib/ricqchet/channels/subscriber_tracker.ex`** — Add:
- `get_cluster_count/2` — RPC to all nodes, sum counts (5s timeout)
- `list_active_cluster/1` — RPC to all nodes, merge results
- Graceful degradation on RPC failure

**`lib/ricqchet/channels/channels.ex`**:
- Update `list_channels/1` → use `list_active_cluster/1`
- Update `get_channel_info/2` → use `get_cluster_count/2`

### Tests
- Single-node returns correct local count
- RPC failure handling (returns partial results)

---

## #117: Connection Management

### Goal
Per-application connection limits, channel limits, force-disconnect API.

### New Files

**`lib/ricqchet/channels/connection_tracker.ex`** — GenServer + ETS:
- `track_connect(app_id, max)` → `:ok | :limit_reached`
- `track_disconnect(app_id)`
- `get_count(app_id)`

**`lib/ricqchet_web/controllers/channel_user_controller.ex`**:
- `DELETE /v1/channels/users/:user_id/connections`
- Broadcasts `"disconnect"` to socket_id pattern

### Changes

**`lib/ricqchet_web/channels/channel_socket.ex`** — Check connection limit on connect

**`lib/ricqchet_web/channels/pubsub_channel.ex`** — Check channel limit on join (only for new channels)

**`lib/ricqchet_web/router.ex`** — Add DELETE route

**`lib/ricqchet/application.ex`** — Add ConnectionTracker to supervision tree

**`config/config.exs`** — Add limits config:
```elixir
config :ricqchet, :channels,
  max_connections_per_application: 1_000,
  max_channels_per_application: 100
```

### Tests
- Connection limit rejection
- Channel limit rejection
- Force disconnect + reconnection
- Count accuracy under concurrency

---

## #118: Relay Integration

### Goal
Messages with `Ricqchet-Channel` header broadcast to channels after delivery.

### Changes

**`lib/ricqchet/delivery/worker.ex`**:
- In success `handle_result/2`: call `maybe_broadcast_to_channel/1`
- Check message headers for `Ricqchet-Channel` (case-insensitive)
- Validate channel name, publish via `Channels.publish_event/5`
- Event name: `relay:message` with message metadata payload
- **Wrapped in rescue** — broadcast failure never affects delivery status

### Design Decisions
- Broadcast happens **after** successful HTTP delivery only
- Fire-and-forget (best effort)
- No tracking/persistence of relay broadcast

### Tests (`test/ricqchet/delivery/worker_test.exs`)
- Header present → broadcast after delivery
- No header → normal delivery
- Broadcast failure doesn't affect delivery status
- Invalid channel name logged, no error
- Case-insensitive header matching

---

## Cross-Cutting Concerns

### Shared Config Changes
Issues #112, #113, and #117 all modify `config/config.exs`. Coordinate to combine:
```elixir
config :ricqchet, Oban,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron, crontab: [{"*/15 * * * *", Ricqchet.Channels.CleanupWorker}]}
  ],
  queues: [default: 5, delivery: 50, dlq_notifications: 10, channel_webhooks: 5]

config :ricqchet, :channels,
  max_connections_per_application: 1_000,
  max_channels_per_application: 100
```

### No New Migrations
All features use existing tables/columns or ETS. No database migrations required.

### Supervision Tree Additions
- `ClientEventRateLimiter` (#110)
- `ConnectionTracker` (#117)
