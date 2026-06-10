export { RicqchetRealtime, RicqchetChannel } from "./client";
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

// Re-export the shared channel-name helpers for convenience.
export {
  validateChannelName,
  channelType,
  type ChannelType,
  type ChannelNameValidation,
} from "../channels";
