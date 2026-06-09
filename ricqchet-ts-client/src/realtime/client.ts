import { RicqchetError } from "../error";
import { validateChannelName } from "../channels";
import {
  defaultSocketFactory,
  syncPresenceDiff,
  syncPresenceState,
  type PhoenixChannel,
  type PhoenixSocket,
} from "./phoenix";
import type {
  ChannelEventHandler,
  ChannelEventMeta,
  PresenceHandlers,
  RealtimePresenceMember,
  RicqchetRealtimeOptions,
  SubscribeOptions,
  Unbind,
} from "./types";

/** Raw Phoenix presence entry: a map of user id → `{ metas: [...] }`. */
type PresenceState = Record<string, { metas?: Array<Record<string, unknown>> }>;

/**
 * Real-time channel client for Ricqchet, built on Phoenix Channels.
 *
 * Connects to the `/channels` WebSocket with a **subscribe-scoped** API key and
 * lets you subscribe to channels by their bare name (no application prefix —
 * the application is derived from the key). Provides Pusher-like ergonomics:
 * `subscribe` → `bind`, plus presence and client events.
 *
 * @example
 * ```typescript
 * const rt = new RicqchetRealtime({
 *   url: "wss://ricqchet.example.com",
 *   apiKey: process.env.NEXT_PUBLIC_RICQCHET_SUBSCRIBE_KEY!,
 *   userId: currentUser.id,
 * });
 *
 * const channel = rt.subscribe("private-order-123");
 * channel.bind("order:updated", () => refetchOrder());
 * ```
 */
export class RicqchetRealtime {
  private readonly socket: PhoenixSocket;
  private readonly channels = new Map<string, RicqchetChannel>();
  // Reference count per channel so multiple subscribers (e.g. two components
  // bound to the same channel) only leave once the last one unsubscribes.
  private readonly refCounts = new Map<string, number>();
  private connected = false;

  constructor(options: RicqchetRealtimeOptions) {
    const endpoint = deriveEndpoint(options.url, options.socketEndpoint);

    const params: Record<string, unknown> = {
      api_key: options.apiKey,
      ...options.params,
    };
    if (options.userId != null) params.user_id = options.userId;
    if (options.userInfo != null)
      params.user_info = JSON.stringify(options.userInfo);

    const factory = options.socketFactory ?? defaultSocketFactory;
    this.socket = factory(endpoint, { ...options.socketOptions, params });
  }

  /** Opens the WebSocket connection. Called automatically by {@link subscribe}. */
  connect(): void {
    if (this.connected) return;
    this.connected = true;
    this.socket.connect();
  }

  /** Closes the connection and tears down all channel subscriptions. */
  disconnect(): void {
    for (const channel of this.channels.values()) channel.leave();
    this.channels.clear();
    this.refCounts.clear();
    this.connected = false;
    this.socket.disconnect();
  }

  /**
   * Subscribes to a channel by its bare name and returns a {@link RicqchetChannel}.
   * Re-subscribing to an already-joined channel returns the existing instance and
   * increments its reference count (see {@link unsubscribe}).
   *
   * @throws {RicqchetError} `validation_error` if the channel name is invalid.
   */
  subscribe(
    channelName: string,
    options: SubscribeOptions = {}
  ): RicqchetChannel {
    const validation = validateChannelName(channelName);
    if (!validation.valid) {
      throw new RicqchetError("validation_error", validation.reason);
    }

    const existing = this.channels.get(channelName);
    if (existing) {
      this.refCounts.set(
        channelName,
        (this.refCounts.get(channelName) ?? 0) + 1
      );
      return existing;
    }

    this.connect();

    const joinParams: Record<string, unknown> = { ...options.params };
    if (options.lastEventId != null)
      joinParams.last_event_id = options.lastEventId;

    const phoenixChannel = this.socket.channel(channelName, joinParams);
    const channel = new RicqchetChannel(channelName, phoenixChannel);
    this.channels.set(channelName, channel);
    this.refCounts.set(channelName, 1);
    channel.join();
    return channel;
  }

  /**
   * Releases one subscription to a channel. The channel is only left once its
   * reference count reaches zero, so it stays alive while other subscribers
   * (e.g. another mounted component) still hold it. No-op if not subscribed.
   */
  unsubscribe(channelName: string): void {
    const channel = this.channels.get(channelName);
    if (!channel) return;

    const remaining = (this.refCounts.get(channelName) ?? 1) - 1;
    if (remaining > 0) {
      this.refCounts.set(channelName, remaining);
      return;
    }

    this.refCounts.delete(channelName);
    channel.leave();
    this.channels.delete(channelName);
  }

  /** Returns the channel wrapper for an active subscription, if any. */
  channel(channelName: string): RicqchetChannel | undefined {
    return this.channels.get(channelName);
  }

  /** Registers a callback for when the socket opens. */
  onOpen(callback: () => void): void {
    this.socket.onOpen(callback);
  }

  /** Registers a callback for when the socket closes. */
  onClose(callback: (event?: unknown) => void): void {
    this.socket.onClose(callback);
  }

  /** Registers a callback for socket-level errors (e.g. auth/connection failures). */
  onError(callback: (error?: unknown) => void): void {
    this.socket.onError(callback);
  }

  /** Whether the underlying socket is currently connected. */
  isConnected(): boolean {
    return this.socket.isConnected();
  }

  /** Escape hatch: the underlying Phoenix socket. */
  get rawSocket(): PhoenixSocket {
    return this.socket;
  }
}

/**
 * A subscription to a single Ricqchet channel. Obtained from
 * {@link RicqchetRealtime.subscribe}.
 */
export class RicqchetChannel {
  private presenceState: PresenceState = {};
  private presenceBound = false;
  private joined = false;
  private hadSubscriptionError = false;
  private lastSubscriptionError: unknown;
  private readonly subscribedListeners = new Set<() => void>();
  private readonly subscriptionErrorListeners = new Set<
    (reason?: unknown) => void
  >();
  private readonly connectionStateListeners = new Set<
    (subscribed: boolean) => void
  >();

  constructor(
    /** The bare channel name. */
    readonly name: string,
    private readonly channel: PhoenixChannel
  ) {}

  /** The Phoenix channel state: `"joining" | "joined" | "leaving" | "closed" | "errored"`. */
  get state(): string {
    return this.channel.state;
  }

  /** Whether the subscription is currently active (joined and not dropped). */
  get isSubscribed(): boolean {
    return this.joined;
  }

  /**
   * @internal Joins the channel and tracks the subscription ack/error. Called
   * by {@link RicqchetRealtime.subscribe}; not part of the public surface.
   */
  join(): this {
    const push = this.channel.join();
    push.receive("ok", () => this.handleJoined());
    push.receive("error", (reason) => this.handleJoinError(reason));
    // Phoenix auto-rejoins on reconnect, but a dropped/errored channel must not
    // keep reporting `isSubscribed === true`. Note: a *successful* auto-rejoin
    // is not re-detected here (the initial join push fires once), so treat
    // `onSubscribed` as the initial-ack signal.
    this.channel.onError(() => this.setJoined(false));
    this.channel.onClose(() => this.setJoined(false));
    return this;
  }

  private handleJoined(): void {
    this.hadSubscriptionError = false;
    this.lastSubscriptionError = undefined;
    this.setJoined(true);
    for (const cb of this.subscribedListeners) cb();
  }

  private handleJoinError(reason: unknown): void {
    this.hadSubscriptionError = true;
    this.lastSubscriptionError = reason;
    this.setJoined(false);
    for (const cb of this.subscriptionErrorListeners) cb(reason);
  }

  private setJoined(value: boolean): void {
    if (this.joined === value) return;
    this.joined = value;
    for (const cb of this.connectionStateListeners) cb(value);
  }

  /**
   * Registers a callback fired when the subscription is acknowledged. Fires
   * immediately if already subscribed.
   *
   * @returns A function that removes the callback.
   */
  onSubscribed(callback: () => void): Unbind {
    this.subscribedListeners.add(callback);
    if (this.joined) callback();
    return () => this.subscribedListeners.delete(callback);
  }

  /**
   * Registers a callback fired when the subscription is rejected (e.g. the auth
   * endpoint denied a private/presence channel). Replays the last error to
   * callbacks registered after the rejection.
   *
   * @returns A function that removes the callback.
   */
  onSubscriptionError(callback: (reason?: unknown) => void): Unbind {
    this.subscriptionErrorListeners.add(callback);
    if (this.hadSubscriptionError) callback(this.lastSubscriptionError);
    return () => this.subscriptionErrorListeners.delete(callback);
  }

  /**
   * Registers a callback fired when the subscription becomes active (`true`, on
   * join ack) or inactive (`false`, on join error, channel error, or close).
   *
   * @returns A function that removes the callback.
   */
  onConnectionStateChange(callback: (subscribed: boolean) => void): Unbind {
    this.connectionStateListeners.add(callback);
    return () => this.connectionStateListeners.delete(callback);
  }

  /**
   * Binds a handler to a server-published event. The handler receives the
   * event's `data` payload and {@link ChannelEventMeta}.
   *
   * @returns A function that unbinds the handler.
   */
  bind(event: string, handler: ChannelEventHandler): Unbind {
    const ref = this.channel.on(event, (response) => {
      handler(extractData(response), buildMeta(response));
    });
    return () => this.channel.off(event, ref);
  }

  /**
   * Sends a client event to other subscribers (private/presence channels only).
   * Event names must start with `client-`.
   *
   * @returns A promise that resolves on server ack, or rejects with a
   *   {@link RicqchetError} (e.g. `rate_limited`, `forbidden`).
   */
  trigger(event: string, payload: unknown, timeout?: number): Promise<void> {
    if (!event.startsWith("client-")) {
      return Promise.reject(
        new RicqchetError(
          "validation_error",
          `client event names must start with "client-" (got "${event}")`
        )
      );
    }

    return new Promise<void>((resolve, reject) => {
      const push = this.channel.push(event, (payload ?? {}) as object, timeout);
      push.receive("ok", () => resolve());
      push.receive("error", (response) => reject(clientEventError(response)));
      push.receive("timeout", () =>
        reject(new RicqchetError("connection_error", "client event timed out"))
      );
    });
  }

  /**
   * Subscribes to presence on a `presence-` channel. Tracks member state from
   * the server's `presence_state`/`presence_diff` messages and invokes the
   * provided callbacks.
   *
   * @returns A function that unbinds the presence handlers.
   */
  bindPresence(handlers: PresenceHandlers): Unbind {
    this.presenceBound = true;

    // `apply` runs Phoenix's canonical merge (which correctly tracks members
    // with multiple connections/metas). We then derive *member-level* join/leave
    // by comparing membership before/after, so onJoin/onLeave fire once when a
    // member truly appears/disappears — not once per connection (which is what
    // Phoenix's per-meta callbacks do).
    const applyPresence = (apply: () => void) => {
      const before = new Map(this.members().map((m) => [m.userId, m]));
      apply();
      const afterIds = new Set(Object.keys(this.presenceState));

      for (const id of afterIds) {
        if (!before.has(id))
          handlers.onJoin?.(toMember(id, this.presenceState[id]));
      }
      for (const [id, member] of before) {
        if (!afterIds.has(id)) handlers.onLeave?.(member);
      }
      handlers.onSync?.(this.members());
    };

    const stateRef = this.channel.on("presence_state", (raw) => {
      applyPresence(() => {
        this.presenceState = syncPresenceState(
          this.presenceState,
          (raw ?? {}) as PresenceState
        );
      });
    });

    const diffRef = this.channel.on("presence_diff", (raw) => {
      applyPresence(() => {
        const diff = (raw ?? {}) as {
          joins?: PresenceState;
          leaves?: PresenceState;
        };
        this.presenceState = syncPresenceDiff(this.presenceState, diff);
      });
    });

    return () => {
      this.channel.off("presence_state", stateRef);
      this.channel.off("presence_diff", diffRef);
    };
  }

  /** The current presence members. Empty until presence syncs (see {@link bindPresence}). */
  members(): RealtimePresenceMember[] {
    return Object.entries(this.presenceState).map(([id, presence]) =>
      toMember(id, presence)
    );
  }

  /** Registers a callback for when this channel errors. */
  onError(callback: (reason?: unknown) => void): void {
    this.channel.onError(callback);
  }

  /** Registers a callback for when this channel closes. */
  onClose(callback: () => void): void {
    this.channel.onClose(callback);
  }

  /** Leaves the channel. Prefer {@link RicqchetRealtime.unsubscribe}. */
  leave(): void {
    this.channel.leave();
  }

  /** Whether presence handlers are bound on this channel. */
  get hasPresence(): boolean {
    return this.presenceBound;
  }

  /** Escape hatch: the underlying Phoenix channel. */
  get rawChannel(): PhoenixChannel {
    return this.channel;
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/** Derives the `<ws>/channels` socket endpoint from a base URL. */
function deriveEndpoint(url: string, override?: string): string {
  if (override) return override;

  let endpoint = url
    .replace(/\/+$/, "")
    .replace(/^http:\/\//, "ws://")
    .replace(/^https:\/\//, "wss://");

  if (!/^wss?:\/\//.test(endpoint)) {
    endpoint = `wss://${endpoint.replace(/^\/\//, "")}`;
  }
  if (!/\/channels$/.test(endpoint)) {
    endpoint = `${endpoint}/channels`;
  }
  return endpoint;
}

/** Unwraps a server event payload to its `data`, falling back to the raw value. */
function extractData(response: unknown): unknown {
  if (response && typeof response === "object" && "data" in response) {
    return (response as { data: unknown }).data;
  }
  return response;
}

function buildMeta(response: unknown): ChannelEventMeta {
  const obj = (response ?? {}) as Record<string, unknown>;
  const meta: ChannelEventMeta = { raw: response };
  if (typeof obj.channel === "string") meta.channel = obj.channel;
  if (typeof obj.sequence === "number") meta.sequence = obj.sequence;
  // Client events carry the sender's user_id; cached events carry the event id.
  if (typeof obj.user_id === "string") meta.userId = obj.user_id;
  if (typeof obj.id === "string") meta.eventId = obj.id;
  return meta;
}

function toMember(
  userId: string,
  presence: { metas?: Array<Record<string, unknown>> }
): RealtimePresenceMember {
  const meta = presence?.metas?.[0] ?? {};
  return {
    userId,
    userInfo: (meta.user_info as Record<string, unknown>) ?? null,
    joinedAt: typeof meta.joined_at === "number" ? meta.joined_at : null,
  };
}

/** Maps a client-event error reply to a {@link RicqchetError}. */
function clientEventError(response: unknown): RicqchetError {
  const reason =
    response && typeof response === "object" && "reason" in response
      ? String((response as { reason: unknown }).reason)
      : "client event rejected";

  const type =
    reason === "rate_limited"
      ? "rate_limited"
      : reason === "client_events_not_allowed"
        ? "forbidden"
        : "bad_request";

  return new RicqchetError(type, reason, null, { reason });
}
