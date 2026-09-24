// ─── Channel Types ───────────────────────────────────────────────────────────

interface TriggerEventBase {
  /** Event name (1-255 chars) */
  event: string;
  /** Arbitrary JSON payload */
  data?: unknown;
  /** Socket ID to exclude sender from receiving the event */
  socketId?: string;
}

interface TriggerSingleChannel extends TriggerEventBase {
  /** Single channel name */
  channel: string;
  channels?: never;
}

interface TriggerMultipleChannels extends TriggerEventBase {
  channel?: never;
  /** Multiple channel names (max 10) */
  channels: string[];
}

export type TriggerEventParams = TriggerSingleChannel | TriggerMultipleChannels;

export interface TriggerEventResult {
  eventIds: string[];
  channel?: string;
  channels?: string[];
}

export interface BatchTriggerParams {
  batch: Array<{
    channel: string;
    event: string;
    data?: unknown;
    socketId?: string;
  }>;
}

export interface BatchTriggerResult {
  results: Array<{
    channel: string;
    event: string;
    eventId: string | null;
    status: "ok" | "error";
    error: string | null;
  }>;
}

export interface Channel {
  name: string;
  subscriberCount: number;
  type: "public" | "private" | "presence";
}

export interface ChannelInfo extends Channel {
  occupied: boolean;
  members: PresenceMember[] | null;
}

export interface ChannelEvent {
  id: string;
  channel: string;
  event: string;
  data: unknown;
  sequence: number;
  insertedAt: string;
}

export interface PresenceMember {
  userId: string;
  userInfo: Record<string, unknown> | null;
  /** Unix seconds the member joined, when provided by the server. */
  joinedAt: number | null;
}

export interface DisconnectResult {
  status: string;
  userId: string;
}

// ─── Relay → Channel Broadcast ───────────────────────────────────────────────

/**
 * Event name broadcast to a channel when a message published with
 * `broadcastChannel` is successfully delivered.
 */
export const RELAY_MESSAGE_EVENT = "relay:message";

/**
 * The `data` payload of a {@link RELAY_MESSAGE_EVENT} channel event (wire
 * format, as received by `RicqchetChannel.bind`).
 */
export interface RelayMessageEventData {
  message_id: string;
  destination_url: string;
  /** The raw message body that was delivered. */
  payload: string | null;
}
