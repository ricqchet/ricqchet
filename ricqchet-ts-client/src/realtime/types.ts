import type { SocketFactory } from "./phoenix";

/**
 * Configuration for {@link RicqchetRealtime}.
 */
export interface RicqchetRealtimeOptions {
  /**
   * Base URL of your Ricqchet server. Accepts `http(s)://` or `ws(s)://`; the
   * `/channels` WebSocket endpoint is derived automatically (override with
   * {@link socketEndpoint}).
   */
  url: string;
  /**
   * A **`subscribe`-scoped** API key. Subscribe keys are browser-safe — they can
   * only open this WebSocket and are rejected on every REST endpoint. Do **not**
   * ship a full `relay` key to untrusted clients. Mint a subscribe key with
   * `POST /v1/applications/:id/api-keys` `{ "scope": "subscribe" }`.
   */
  apiKey: string;
  /**
   * Provisional, client-supplied user identifier (default: `"anonymous"`).
   * Treated as **unverified** — your channel auth endpoint should bind the
   * authoritative identity for private/presence channels.
   */
  userId?: string;
  /** Provisional, client-supplied user metadata (JSON-encoded over the wire). */
  userInfo?: Record<string, unknown>;
  /** Override the derived `<ws>/channels` socket endpoint entirely. */
  socketEndpoint?: string;
  /** Extra params merged into the WebSocket connection query string. */
  params?: Record<string, unknown>;
  /** Passthrough options for the underlying Phoenix `Socket` (transport, heartbeat, …). */
  socketOptions?: Record<string, unknown>;
  /** Injects the socket implementation (custom transport or a test fake). */
  socketFactory?: SocketFactory;
}

/** A member of a presence channel. */
export interface RealtimePresenceMember {
  userId: string;
  userInfo: Record<string, unknown> | null;
  /** Unix seconds the member joined, when provided by the server. */
  joinedAt: number | null;
}

/** Metadata accompanying a channel event. */
export interface ChannelEventMeta {
  /** The channel the event was published to. */
  channel?: string;
  /** Monotonic per-channel sequence number, when the channel persists history. */
  sequence?: number;
  /** The sender's `user_id`, for `client-` events. */
  userId?: string;
  /** The event id, for `ricqchet:cached_event` (use as `lastEventId` for recovery). */
  eventId?: string;
  /** The raw, unwrapped server payload. */
  raw: unknown;
}

/**
 * Handler for a bound channel event. Receives the event's `data` payload and
 * metadata. For server-published domain events the first argument is the
 * `data` you published; for system events (e.g. `ricqchet:cached_event`) read
 * {@link ChannelEventMeta.raw}.
 */
export type ChannelEventHandler = (
  data: unknown,
  meta: ChannelEventMeta
) => void;

/** Unbinds a previously bound handler. */
export type Unbind = () => void;

/** Options for {@link RicqchetRealtime.subscribe}. */
export interface SubscribeOptions {
  /**
   * Replay events published after this event id on (re)join, for gap recovery.
   * Obtain ids from `ricqchet:cached_event` or `GET /v1/channels/:name/events`.
   */
  lastEventId?: string;
  /** Extra params merged into the channel join payload. */
  params?: Record<string, unknown>;
}

/** Presence lifecycle callbacks for {@link RicqchetChannel.bindPresence}. */
export interface PresenceHandlers {
  /** Called with the full member list whenever presence state changes. */
  onSync?: (members: RealtimePresenceMember[]) => void;
  /** Called when a member joins. */
  onJoin?: (member: RealtimePresenceMember) => void;
  /** Called when a member leaves. */
  onLeave?: (member: RealtimePresenceMember) => void;
}
