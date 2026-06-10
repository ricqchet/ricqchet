import { describe, it, expect, vi } from "vitest";
import { RicqchetRealtime } from "../src/realtime/client";
import { RicqchetError } from "../src/error";
import type {
  PhoenixChannel,
  PhoenixPush,
  PhoenixSocket,
  SocketFactory,
} from "../src/realtime/phoenix";
import type { RicqchetRealtimeOptions } from "../src/realtime/types";

// ─── Controllable Phoenix fakes ──────────────────────────────────────────────

class FakePush implements PhoenixPush {
  handlers: Record<string, (response?: unknown) => void> = {};
  receive(
    status: "ok" | "error" | "timeout",
    callback: (response?: unknown) => void
  ) {
    this.handlers[status] = callback;
    return this;
  }
  emit(status: "ok" | "error" | "timeout", response?: unknown) {
    this.handlers[status]?.(response);
  }
}

class FakeChannel implements PhoenixChannel {
  state = "joining";
  joinPush = new FakePush();
  listeners: Record<string, Array<(response?: unknown) => void>> = {};
  pushed: Array<{ event: string; payload: object; push: FakePush }> = [];

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
  on(event: string, callback: (response?: unknown) => void) {
    (this.listeners[event] ||= []).push(callback);
    return this.listeners[event].length - 1;
  }
  off(event: string, ref?: number) {
    if (ref != null && this.listeners[event])
      this.listeners[event][ref] = () => {};
  }
  push(event: string, payload: object) {
    const push = new FakePush();
    this.pushed.push({ event, payload, push });
    return push;
  }
  closeCbs: Array<() => void> = [];
  errorCbs: Array<(reason?: unknown) => void> = [];
  onClose(cb: () => void) {
    this.closeCbs.push(cb);
    return 0;
  }
  onError(cb: (reason?: unknown) => void) {
    this.errorCbs.push(cb);
    return 0;
  }

  // test helpers
  emit(event: string, payload?: unknown) {
    (this.listeners[event] ?? []).forEach((cb) => cb(payload));
  }
  triggerError(reason?: unknown) {
    this.errorCbs.forEach((cb) => cb(reason));
  }
  triggerClose() {
    this.closeCbs.forEach((cb) => cb());
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
  disconnect(callback?: () => void) {
    this.connected = false;
    callback?.();
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

function setup(options: Partial<RicqchetRealtimeOptions> = {}) {
  let socket!: FakeSocket;
  const factory: SocketFactory = (endpoint, opts) => {
    socket = new FakeSocket(
      endpoint,
      opts as { params: Record<string, unknown> }
    );
    return socket;
  };
  const rt = new RicqchetRealtime({
    url: "https://ricqchet.example.com",
    apiKey: "sub_test_key",
    socketFactory: factory,
    ...options,
  });
  return { rt, getSocket: () => socket };
}

// ─── Tests ───────────────────────────────────────────────────────────────────

describe("RicqchetRealtime — connection", () => {
  it("derives the /channels wss endpoint and connect params", () => {
    const { rt, getSocket } = setup({
      userId: "user-1",
      userInfo: { name: "Ada" },
    });
    rt.connect();
    const socket = getSocket();

    expect(socket.endpoint).toBe("wss://ricqchet.example.com/channels");
    expect(socket.options.params).toEqual({
      api_key: "sub_test_key",
      user_id: "user-1",
      user_info: JSON.stringify({ name: "Ada" }),
    });
    expect(socket.connected).toBe(true);
  });

  it("converts http(s) and respects an explicit socketEndpoint", () => {
    const { rt: a, getSocket: ga } = setup({ url: "http://localhost:4000" });
    a.connect();
    expect(ga().endpoint).toBe("ws://localhost:4000/channels");

    const { rt: b, getSocket: gb } = setup({
      socketEndpoint: "wss://edge.example.com/rt",
    });
    b.connect();
    expect(gb().endpoint).toBe("wss://edge.example.com/rt");
  });
});

describe("RicqchetRealtime — subscribe", () => {
  it("joins using the bare channel name as the topic (backend #127)", () => {
    const { rt, getSocket } = setup();
    rt.subscribe("private-order-123");

    const socket = getSocket();
    expect(socket.connected).toBe(true); // auto-connect
    expect(socket.channels).toHaveLength(1);
    expect(socket.channels[0].topic).toBe("private-order-123");
  });

  it("throws a validation_error for invalid channel names", () => {
    const { rt } = setup();
    expect(() => rt.subscribe("bad:name")).toThrow(RicqchetError);
  });

  it("returns the same channel instance on repeat subscribe", () => {
    const { rt, getSocket } = setup();
    const a = rt.subscribe("room");
    const b = rt.subscribe("room");
    expect(a).toBe(b);
    expect(getSocket().channels).toHaveLength(1);
  });

  it("forwards lastEventId as a join param for gap recovery", () => {
    const { rt, getSocket } = setup();
    rt.subscribe("orders.us.west", { lastEventId: "evt-9" });
    expect(getSocket().channels[0].params).toMatchObject({
      last_event_id: "evt-9",
    });
  });

  it("tracks subscription ack/error state", () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("room");
    const onSub = vi.fn();
    channel.onSubscribed(onSub);

    expect(channel.isSubscribed).toBe(false);
    getSocket().channels[0].joinPush.emit("ok");
    expect(channel.isSubscribed).toBe(true);
    expect(onSub).toHaveBeenCalledOnce();

    const errChannel = rt.subscribe("other");
    const onErr = vi.fn();
    errChannel.onSubscriptionError(onErr);
    getSocket().channels[1].joinPush.emit("error", { reason: "forbidden" });
    expect(onErr).toHaveBeenCalledWith({ reason: "forbidden" });
  });

  it("unsubscribe leaves and forgets the channel", () => {
    const { rt, getSocket } = setup();
    rt.subscribe("room");
    rt.unsubscribe("room");
    expect(getSocket().channels[0].state).toBe("leaving");
    expect(rt.channel("room")).toBeUndefined();
  });

  it("refcounts shared subscriptions — leaves only on the last unsubscribe", () => {
    const { rt, getSocket } = setup();
    const a = rt.subscribe("room");
    const b = rt.subscribe("room");
    expect(a).toBe(b);

    rt.unsubscribe("room");
    expect(getSocket().channels[0].state).not.toBe("leaving"); // still held by `b`
    expect(rt.channel("room")).toBe(a);

    rt.unsubscribe("room");
    expect(getSocket().channels[0].state).toBe("leaving"); // last subscriber left
    expect(rt.channel("room")).toBeUndefined();
  });
});

describe("RicqchetChannel — events", () => {
  it("delivers unwrapped data plus metadata to bound handlers", () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("private-order-1");
    const handler = vi.fn();
    channel.bind("order:updated", handler);

    getSocket().channels[0].emit("order:updated", {
      data: { orderId: "1" },
      channel: "private-order-1",
      sequence: 7,
    });

    expect(handler).toHaveBeenCalledWith(
      { orderId: "1" },
      expect.objectContaining({ channel: "private-order-1", sequence: 7 })
    );
  });

  it("unbind stops further delivery", () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("room");
    const handler = vi.fn();
    const unbind = channel.bind("ping", handler);
    unbind();
    getSocket().channels[0].emit("ping", { data: 1 });
    expect(handler).not.toHaveBeenCalled();
  });

  it("rejects client events that do not start with 'client-'", async () => {
    const { rt } = setup();
    const channel = rt.subscribe("private-room");
    await expect(channel.trigger("typing", {})).rejects.toThrow(RicqchetError);
  });

  it("resolves a client event on server ack", async () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("private-room");
    const promise = channel.trigger("client-typing", { at: 1 });

    const pushed = getSocket().channels[0].pushed[0];
    expect(pushed.event).toBe("client-typing");
    pushed.push.emit("ok");
    await expect(promise).resolves.toBeUndefined();
  });

  it("maps a rate_limited reply to a RicqchetError", async () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("private-room");
    const promise = channel.trigger("client-typing", {});
    getSocket().channels[0].pushed[0].push.emit("error", {
      reason: "rate_limited",
    });

    await expect(promise).rejects.toMatchObject({ type: "rate_limited" });
  });

  it("exposes the sender user_id on client-event meta", () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("private-room");
    const handler = vi.fn();
    channel.bind("client-typing", handler);

    getSocket().channels[0].emit("client-typing", {
      data: { at: 1 },
      channel: "private-room",
      user_id: "sender-9",
    });

    expect(handler).toHaveBeenCalledWith(
      { at: 1 },
      expect.objectContaining({ userId: "sender-9" })
    );
  });

  it("exposes the event id on a cached-event meta", () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("room");
    const handler = vi.fn();
    channel.bind("ricqchet:cached_event", handler);

    getSocket().channels[0].emit("ricqchet:cached_event", {
      data: { x: 1 },
      channel: "room",
      event: "thing.happened",
      sequence: 3,
      id: "evt-77",
    });

    expect(handler).toHaveBeenCalledWith(
      { x: 1 },
      expect.objectContaining({ eventId: "evt-77", sequence: 3 })
    );
  });
});

describe("RicqchetChannel — subscription liveness", () => {
  it("goes unsubscribed on channel error/close and notifies listeners", () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("room");
    const states: boolean[] = [];
    channel.onConnectionStateChange((s) => states.push(s));

    getSocket().channels[0].joinPush.emit("ok");
    expect(channel.isSubscribed).toBe(true);

    getSocket().channels[0].triggerError();
    expect(channel.isSubscribed).toBe(false);

    expect(states).toEqual([true, false]);
  });

  it("replays the last subscription error to a late listener", () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("private-room");
    getSocket().channels[0].joinPush.emit("error", { reason: "forbidden" });

    const onErr = vi.fn();
    channel.onSubscriptionError(onErr); // registered AFTER the error
    expect(onErr).toHaveBeenCalledWith({ reason: "forbidden" });
  });
});

describe("RicqchetChannel — presence", () => {
  it("tracks presence_state and presence_diff", () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("presence-lobby");
    const onSync = vi.fn();
    const onJoin = vi.fn();
    const onLeave = vi.fn();
    channel.bindPresence({ onSync, onJoin, onLeave });

    const fake = getSocket().channels[0];
    fake.emit("presence_state", {
      u1: { metas: [{ user_info: { name: "Ada" }, joined_at: 100 }] },
    });

    expect(channel.members()).toEqual([
      { userId: "u1", userInfo: { name: "Ada" }, joinedAt: 100 },
    ]);
    expect(onJoin).toHaveBeenCalledWith({
      userId: "u1",
      userInfo: { name: "Ada" },
      joinedAt: 100,
    });
    expect(onSync).toHaveBeenCalled();

    fake.emit("presence_diff", {
      joins: { u2: { metas: [{ user_info: null, joined_at: 200 }] } },
      leaves: { u1: { metas: [{}] } },
    });

    expect(channel.members().map((m) => m.userId)).toEqual(["u2"]);
    expect(onLeave).toHaveBeenCalledWith(
      expect.objectContaining({ userId: "u1" })
    );
  });

  it("keeps a multi-connection member until their last meta leaves", () => {
    const { rt, getSocket } = setup();
    const channel = rt.subscribe("presence-lobby");
    const onLeave = vi.fn();
    channel.bindPresence({ onLeave });
    const fake = getSocket().channels[0];

    // One user (u1) connected from two tabs => two metas, keyed by phx_ref.
    fake.emit("presence_state", {
      u1: {
        metas: [
          { phx_ref: "r1", user_info: { name: "Ada" }, joined_at: 1 },
          { phx_ref: "r2", user_info: { name: "Ada" }, joined_at: 2 },
        ],
      },
    });
    expect(channel.members().map((m) => m.userId)).toEqual(["u1"]);

    // One tab closes: u1 must REMAIN present (this is the bug the review caught).
    fake.emit("presence_diff", {
      joins: {},
      leaves: { u1: { metas: [{ phx_ref: "r1" }] } },
    });
    expect(channel.members().map((m) => m.userId)).toEqual(["u1"]);
    expect(onLeave).not.toHaveBeenCalled();

    // Last tab closes: now u1 leaves.
    fake.emit("presence_diff", {
      joins: {},
      leaves: { u1: { metas: [{ phx_ref: "r2" }] } },
    });
    expect(channel.members()).toEqual([]);
    expect(onLeave).toHaveBeenCalledWith(
      expect.objectContaining({ userId: "u1" })
    );
  });
});
