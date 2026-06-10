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
  /** Multiple channel names (max 100) */
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
  joinedAt: string;
}

export interface DisconnectResult {
  status: string;
  userId: string;
}
