export { RicqchetRealtime, RicqchetChannel } from "./client";
export { SystemEvents } from "./types";
export type {
  RicqchetRealtimeOptions,
  RealtimePresenceMember,
  ChannelEventMeta,
  ChannelEventHandler,
  SubscribeOptions,
  PresenceHandlers,
  Unbind,
} from "./types";
export type {
  PhoenixSocket,
  PhoenixChannel,
  PhoenixPush,
  SocketFactory,
  SocketFactoryOptions,
} from "./phoenix";

export { RELAY_MESSAGE_EVENT } from "../types";
export type { RelayMessageEventData } from "../types";

// Re-export the shared channel-name helpers for convenience.
export {
  validateChannelName,
  channelType,
  type ChannelType,
  type ChannelNameValidation,
} from "../channels";
