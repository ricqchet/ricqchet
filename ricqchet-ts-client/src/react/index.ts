"use client";

import {
  createContext,
  createElement,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import type { ReactNode } from "react";
import { RicqchetRealtime, RicqchetChannel } from "../realtime/client";
import type {
  ChannelEventHandler,
  RealtimePresenceMember,
  RicqchetRealtimeOptions,
  SubscribeOptions,
} from "../realtime/types";

const RicqchetContext = createContext<RicqchetRealtime | null>(null);

/** Props for {@link RicqchetProvider}. */
export type RicqchetProviderProps = Partial<RicqchetRealtimeOptions> & {
  /** Supply a pre-built client (e.g. for tests or shared instances). */
  client?: RicqchetRealtime;
  children?: ReactNode;
};

/**
 * Provides a single shared {@link RicqchetRealtime} connection to descendants.
 * Pass a **subscribe-scoped** API key — it is safe in the browser.
 *
 * @example
 * ```tsx
 * <RicqchetProvider
 *   url="wss://ricqchet.example.com"
 *   apiKey={process.env.NEXT_PUBLIC_RICQCHET_SUBSCRIBE_KEY!}
 *   userId={session.user.id}
 * >
 *   <App />
 * </RicqchetProvider>
 * ```
 */
export function RicqchetProvider(props: RicqchetProviderProps): ReactNode {
  const { client, children } = props;

  // The connection is created once from the initial options. To change it
  // (url/apiKey/userId/userInfo), remount the provider with a React `key`.
  const optionsRef = useRef(props);

  // Lazily construct exactly one client — useState's initializer runs once, so
  // (unlike useMemo, which React may discard) a second socket can never leak.
  const [realtime] = useState<RicqchetRealtime>(() => {
    if (client) return client;
    const o = optionsRef.current;
    if (!o.url || !o.apiKey) {
      throw new Error(
        "RicqchetProvider requires either a `client` or both `url` and `apiKey`."
      );
    }
    return new RicqchetRealtime({
      url: o.url,
      apiKey: o.apiKey,
      userId: o.userId,
      userInfo: o.userInfo,
      socketEndpoint: o.socketEndpoint,
      params: o.params,
      socketOptions: o.socketOptions,
      socketFactory: o.socketFactory,
    });
  });

  useEffect(() => {
    // Own the connection lifecycle only for clients we created. Connecting here
    // (rather than only lazily in subscribe) makes StrictMode's mount → unmount
    // → mount deterministic: the remount reconnects the same instance.
    if (client) return;
    realtime.connect();
    return () => realtime.disconnect();
  }, [realtime, client]);

  return createElement(RicqchetContext.Provider, { value: realtime }, children);
}

/**
 * Returns the {@link RicqchetRealtime} from the nearest {@link RicqchetProvider}.
 *
 * @throws if used outside a provider.
 */
export function useRicqchet(): RicqchetRealtime {
  const realtime = useContext(RicqchetContext);
  if (!realtime) {
    throw new Error("useRicqchet must be used within a <RicqchetProvider>.");
  }
  return realtime;
}

/**
 * Subscribes to a channel for the lifetime of the component and returns it.
 * Pass `null` to skip subscribing (e.g. while an id is loading).
 *
 * @example
 * ```tsx
 * const channel = useRicqchetChannel(`private-order-${orderId}`);
 * ```
 */
export function useRicqchetChannel(
  channelName: string | null,
  options?: SubscribeOptions
): RicqchetChannel | null {
  const realtime = useContext(RicqchetContext);
  const [channel, setChannel] = useState<RicqchetChannel | null>(null);

  // Re-subscribe only when the channel name (or client) changes — not when the
  // options object identity changes on each render.
  const optionsRef = useRef(options);
  optionsRef.current = options;

  useEffect(() => {
    if (!realtime || !channelName) {
      setChannel(null);
      return;
    }
    const subscribed = realtime.subscribe(channelName, optionsRef.current);
    setChannel(subscribed);
    return () => {
      realtime.unsubscribe(channelName);
      setChannel(null);
    };
  }, [realtime, channelName]);

  return channel;
}

/**
 * Binds a handler to a channel event for the lifetime of the component. The
 * handler may change between renders without re-binding the channel.
 *
 * @example
 * ```tsx
 * useRicqchetEvent(channel, "order:updated", () => refetchOrder());
 * ```
 */
export function useRicqchetEvent(
  channel: RicqchetChannel | null,
  event: string,
  handler: ChannelEventHandler
): void {
  const handlerRef = useRef(handler);
  handlerRef.current = handler;

  useEffect(() => {
    if (!channel) return;
    const unbind = channel.bind(event, (data, meta) =>
      handlerRef.current(data, meta)
    );
    return unbind;
  }, [channel, event]);
}

/**
 * Tracks whether a channel's subscription is currently active (analogous to
 * Pusher's `subscription_succeeded`). Becomes `false` if the channel is dropped
 * or errored, and `true` on the initial join ack.
 */
export function useRicqchetSubscribed(
  channel: RicqchetChannel | null
): boolean {
  const [subscribed, setSubscribed] = useState(channel?.isSubscribed ?? false);

  useEffect(() => {
    if (!channel) {
      setSubscribed(false);
      return;
    }
    setSubscribed(channel.isSubscribed);
    return channel.onConnectionStateChange(setSubscribed);
  }, [channel]);

  return subscribed;
}

/**
 * Tracks presence members on a `presence-` channel.
 *
 * @example
 * ```tsx
 * const { members } = useRicqchetPresence(channel);
 * ```
 */
export function useRicqchetPresence(channel: RicqchetChannel | null): {
  members: RealtimePresenceMember[];
} {
  const [members, setMembers] = useState<RealtimePresenceMember[]>([]);

  useEffect(() => {
    if (!channel) {
      setMembers([]);
      return;
    }
    // Seed from any already-synced presence (shared channel) and clear members
    // from a previous channel before the new channel's first sync arrives.
    setMembers(channel.members());
    const unbind = channel.bindPresence({ onSync: setMembers });
    return unbind;
  }, [channel]);

  return { members };
}

export { RicqchetRealtime, RicqchetChannel };
export type {
  RicqchetRealtimeOptions,
  SubscribeOptions,
  ChannelEventHandler,
  RealtimePresenceMember,
} from "../realtime/types";
