// ─── Phoenix adapter ─────────────────────────────────────────────────────────
//
// The realtime client is built on the official `phoenix` JS package (a peer
// dependency). We depend only on the small subset below, expressed as plain
// interfaces, so the client can be unit-tested with a fake socket and so the
// `phoenix` import is isolated to a single module.

import {
  Presence as PhoenixPresence,
  Socket as PhoenixSocketImpl,
} from "phoenix";

/** Raw Phoenix presence map: `user_id` → `{ metas: [...] }` (one meta per connection). */
export type PresenceMap = Record<
  string,
  { metas?: Array<Record<string, unknown>> }
>;

/** Per-key presence join/leave callback: `(id, currentPresence, newPresence)`. */
export type PresenceSyncCallback = (
  id?: string,
  current?: unknown,
  updated?: unknown
) => void;

/**
 * Canonical Phoenix presence-state sync (full snapshot). Delegates to
 * `Phoenix.Presence.syncState` so multi-connection members (same `user_id`,
 * multiple metas) are merged correctly rather than reimplemented.
 */
export function syncPresenceState(
  current: PresenceMap,
  newState: PresenceMap,
  onJoin?: PresenceSyncCallback,
  onLeave?: PresenceSyncCallback
): PresenceMap {
  return PhoenixPresence.syncState(
    current,
    newState,
    onJoin,
    onLeave
  ) as PresenceMap;
}

/**
 * Canonical Phoenix presence-diff sync (incremental joins/leaves). Delegates to
 * `Phoenix.Presence.syncDiff`, which removes only the leaving metas and keeps a
 * member present while any meta remains.
 */
export function syncPresenceDiff(
  current: PresenceMap,
  diff: { joins?: PresenceMap; leaves?: PresenceMap },
  onJoin?: PresenceSyncCallback,
  onLeave?: PresenceSyncCallback
): PresenceMap {
  return PhoenixPresence.syncDiff(
    current,
    diff as { joins: object; leaves: object },
    onJoin,
    onLeave
  ) as PresenceMap;
}

/** A pending push (channel join / client event), awaiting a server reply. */
export interface PhoenixPush {
  receive(
    status: "ok" | "error" | "timeout",
    callback: (response?: unknown) => void
  ): PhoenixPush;
}

/** The subset of a Phoenix `Channel` the realtime client uses. */
export interface PhoenixChannel {
  state: string;
  topic: string;
  join(timeout?: number): PhoenixPush;
  leave(timeout?: number): PhoenixPush;
  on(event: string, callback: (response?: unknown) => void): number;
  off(event: string, ref?: number): void;
  push(event: string, payload: object, timeout?: number): PhoenixPush;
  onClose(callback: () => void): number;
  onError(callback: (reason?: unknown) => void): number;
}

/** The subset of a Phoenix `Socket` the realtime client uses. */
export interface PhoenixSocket {
  connect(params?: unknown): void;
  disconnect(callback?: () => void, code?: number, reason?: string): void;
  channel(topic: string, chanParams?: object): PhoenixChannel;
  isConnected(): boolean;
  onOpen(callback: () => void): unknown;
  onClose(callback: (event?: unknown) => void): unknown;
  onError(callback: (error?: unknown) => void): unknown;
}

/** Options handed to a {@link SocketFactory} — `params` becomes the WS query string. */
export interface SocketFactoryOptions {
  params: Record<string, unknown>;
  [key: string]: unknown;
}

/**
 * Builds the underlying socket. Defaults to {@link defaultSocketFactory} (the
 * real `phoenix` `Socket`); override it to inject a custom transport or a fake
 * in tests.
 */
export type SocketFactory = (
  endpoint: string,
  options: SocketFactoryOptions
) => PhoenixSocket;

/** Creates a real `phoenix` `Socket`. Requires `phoenix` to be installed. */
export const defaultSocketFactory: SocketFactory = (endpoint, options) =>
  new PhoenixSocketImpl(
    endpoint,
    options as ConstructorParameters<typeof PhoenixSocketImpl>[1]
  ) as unknown as PhoenixSocket;
