// @vitest-environment happy-dom
import { describe, it, expect, vi } from "vitest";
import { act, renderHook } from "@testing-library/react";
import { createElement, type ReactNode } from "react";
import {
  RicqchetProvider,
  useRicqchetChannel,
  useRicqchetEvent,
  useRicqchetSubscribed,
} from "../src/react";
import { RicqchetRealtime } from "../src/realtime/client";
import type {
  PhoenixChannel,
  PhoenixPush,
  PhoenixSocket,
  SocketFactory,
} from "../src/realtime/phoenix";

class FakePush implements PhoenixPush {
  handlers: Record<string, (r?: unknown) => void> = {};
  receive(status: "ok" | "error" | "timeout", cb: (r?: unknown) => void) {
    this.handlers[status] = cb;
    return this;
  }
  emit(status: "ok" | "error" | "timeout", r?: unknown) {
    this.handlers[status]?.(r);
  }
}

class FakeChannel implements PhoenixChannel {
  state = "joining";
  joinPush = new FakePush();
  listeners: Record<string, Array<(r?: unknown) => void>> = {};
  constructor(
    readonly topic: string,
    readonly params: object
  ) {}
  join() {
    return this.joinPush;
  }
  leave() {
    this.state = "leaving";
    return new FakePush();
  }
  on(event: string, cb: (r?: unknown) => void) {
    (this.listeners[event] ||= []).push(cb);
    return this.listeners[event].length - 1;
  }
  off() {}
  push() {
    return new FakePush();
  }
  errorCbs: Array<(reason?: unknown) => void> = [];
  onClose() {
    return 0;
  }
  onError(cb: (reason?: unknown) => void) {
    this.errorCbs.push(cb);
    return 0;
  }
  emit(event: string, payload?: unknown) {
    (this.listeners[event] ?? []).forEach((cb) => cb(payload));
  }
  triggerError(reason?: unknown) {
    this.errorCbs.forEach((cb) => cb(reason));
  }
}

class FakeSocket implements PhoenixSocket {
  connected = false;
  channels: FakeChannel[] = [];
  constructor(
    readonly endpoint: string,
    readonly options: { params: Record<string, unknown> }
  ) {}
  connect() {
    this.connected = true;
  }
  disconnect() {
    this.connected = false;
  }
  channel(topic: string, params: object = {}) {
    const channel = new FakeChannel(topic, params);
    this.channels.push(channel);
    return channel;
  }
  isConnected() {
    return this.connected;
  }
  onOpen() {
    return 0;
  }
  onClose() {
    return 0;
  }
  onError() {
    return 0;
  }
}

function makeClient() {
  let socket!: FakeSocket;
  const factory: SocketFactory = (endpoint, opts) => {
    socket = new FakeSocket(
      endpoint,
      opts as { params: Record<string, unknown> }
    );
    return socket;
  };
  const rt = new RicqchetRealtime({
    url: "wss://ricqchet.example.com",
    apiKey: "sub_key",
    socketFactory: factory,
  });
  return { rt, getSocket: () => socket };
}

function wrapperFor(rt: RicqchetRealtime) {
  return ({ children }: { children: ReactNode }) =>
    createElement(RicqchetProvider, { client: rt }, children);
}

describe("useRicqchetChannel / useRicqchetSubscribed", () => {
  it("subscribes by bare name and tracks the subscription ack", () => {
    const { rt, getSocket } = makeClient();
    const { result } = renderHook(
      () => {
        const channel = useRicqchetChannel("private-order-1");
        return useRicqchetSubscribed(channel);
      },
      { wrapper: wrapperFor(rt) }
    );

    expect(getSocket().channels[0].topic).toBe("private-order-1");
    expect(result.current).toBe(false);

    act(() => getSocket().channels[0].joinPush.emit("ok"));
    expect(result.current).toBe(true);
  });

  it("unsubscribes on unmount", () => {
    const { rt, getSocket } = makeClient();
    const { unmount } = renderHook(() => useRicqchetChannel("room"), {
      wrapper: wrapperFor(rt),
    });
    expect(getSocket().channels[0].state).toBe("joining");
    unmount();
    expect(getSocket().channels[0].state).toBe("leaving");
  });

  it("re-subscribes when the channel name changes", () => {
    const { rt, getSocket } = makeClient();
    const { rerender } = renderHook(
      ({ name }: { name: string }) => useRicqchetChannel(name),
      { initialProps: { name: "room-a" }, wrapper: wrapperFor(rt) }
    );
    rerender({ name: "room-b" });

    const socket = getSocket();
    expect(socket.channels.map((c) => c.topic)).toEqual(["room-a", "room-b"]);
    expect(socket.channels[0].state).toBe("leaving"); // old one left
  });
});

describe("useRicqchetEvent", () => {
  it("invokes the latest handler with unwrapped data", () => {
    const { rt, getSocket } = makeClient();
    const handler = vi.fn();

    renderHook(
      () => {
        const channel = useRicqchetChannel("private-order-1");
        useRicqchetEvent(channel, "order:updated", handler);
      },
      { wrapper: wrapperFor(rt) }
    );

    act(() =>
      getSocket().channels[0].emit("order:updated", {
        data: { orderId: "1" },
        channel: "private-order-1",
      })
    );

    expect(handler).toHaveBeenCalledWith(
      { orderId: "1" },
      expect.objectContaining({ channel: "private-order-1" })
    );
  });
});

describe("shared channel + liveness", () => {
  it("keeps a channel alive until the last subscribing hook unmounts", () => {
    const { rt, getSocket } = makeClient();
    const wrapper = wrapperFor(rt);
    const a = renderHook(() => useRicqchetChannel("room"), { wrapper });
    const b = renderHook(() => useRicqchetChannel("room"), { wrapper });

    const channel = getSocket().channels[0];
    expect(getSocket().channels).toHaveLength(1); // shared, not duplicated

    a.unmount();
    expect(channel.state).not.toBe("leaving"); // `b` still holds it

    b.unmount();
    expect(channel.state).toBe("leaving");
  });

  it("reflects a channel drop in useRicqchetSubscribed", () => {
    const { rt, getSocket } = makeClient();
    const { result } = renderHook(
      () => useRicqchetSubscribed(useRicqchetChannel("room")),
      { wrapper: wrapperFor(rt) }
    );

    act(() => getSocket().channels[0].joinPush.emit("ok"));
    expect(result.current).toBe(true);

    act(() => getSocket().channels[0].triggerError());
    expect(result.current).toBe(false);
  });
});
