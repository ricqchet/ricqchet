import { describe, it, expect, vi } from "vitest";
import { createHmac } from "crypto";
import {
  createChannelAuthRoute,
  verifyChannelWebhookRequest,
} from "../src/next";

function authRequest(
  body: unknown,
  url = "https://app.example.com/api/ricqchet/channel-auth"
): Request {
  return new Request(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

describe("createChannelAuthRoute", () => {
  it("allows with 200 and an empty body when the authorizer returns true", async () => {
    const handler = createChannelAuthRoute(() => true);
    const res = await handler(
      authRequest({ channel: "private-x", user_id: "u1", socket_id: "s1" })
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({});
  });

  it("denies with 403 when the authorizer returns false", async () => {
    const handler = createChannelAuthRoute(() => false);
    const res = await handler(
      authRequest({ channel: "private-x", user_id: "u1", socket_id: "s1" })
    );
    expect(res.status).toBe(403);
  });

  it("binds verified identity from an object result (backend #129)", async () => {
    const handler = createChannelAuthRoute(() => ({
      userId: "verified-7",
      userInfo: { name: "Ada", role: "member" },
    }));
    const res = await handler(
      authRequest({
        channel: "presence-lobby",
        user_id: "spoofed",
        socket_id: "s1",
      })
    );
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      user_id: "verified-7",
      user_info: { name: "Ada", role: "member" },
    });
  });

  it("passes the parsed params to the authorizer", async () => {
    const authorize = vi.fn().mockReturnValue(true);
    const handler = createChannelAuthRoute(authorize);
    await handler(
      authRequest({
        channel: "private-orders",
        user_id: "u1",
        socket_id: "sock-9",
      })
    );
    expect(authorize).toHaveBeenCalledWith(
      { channel: "private-orders", userId: "u1", socketId: "sock-9" },
      expect.any(Request)
    );
  });

  it("returns 400 for a non-JSON or malformed body", async () => {
    const handler = createChannelAuthRoute(() => true);
    expect((await handler(authRequest("not json"))).status).toBe(400);
    expect(
      (await handler(authRequest({ user_id: "u1", socket_id: "s1" }))).status
    ).toBe(400); // missing channel
  });

  it("returns 500 (fail-closed) when the authorizer throws", async () => {
    const handler = createChannelAuthRoute(() => {
      throw new Error("db down");
    });
    const res = await handler(
      authRequest({ channel: "private-x", user_id: "u1", socket_id: "s1" })
    );
    expect(res.status).toBe(500);
  });

  describe("shared secret", () => {
    const handler = createChannelAuthRoute(() => true, { secret: "shh" });
    const body = { channel: "private-x", user_id: "u1", socket_id: "s1" };

    it("rejects requests without the secret", async () => {
      const res = await handler(authRequest(body));
      expect(res.status).toBe(403);
    });

    it("accepts the secret via query param", async () => {
      const res = await handler(
        authRequest(body, "https://app.example.com/api/auth?secret=shh")
      );
      expect(res.status).toBe(200);
    });

    it("accepts the secret via header", async () => {
      const req = new Request("https://app.example.com/api/auth", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-ricqchet-auth-secret": "shh",
        },
        body: JSON.stringify(body),
      });
      expect((await handler(req)).status).toBe(200);
    });
  });
});

describe("verifyChannelWebhookRequest", () => {
  const secret = Buffer.from("test-secret-32-bytes-long-here!!");

  function signedRequest(payload: object, signingSecret = secret): Request {
    const body = JSON.stringify(payload);
    const ts = Math.floor(Date.now() / 1000);
    const sig = createHmac("sha256", signingSecret)
      .update(`${ts}.${body}`)
      .digest("hex");
    return new Request("https://app.example.com/api/ricqchet/channel-webhook", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-ricqchet-signature": `t=${ts},v1=${sig}`,
      },
      body,
    });
  }

  it("verifies and types a presence member webhook", async () => {
    const req = signedRequest({
      event: "member:added",
      channel: "presence-lobby",
      timestamp: "2026-01-01T00:00:00Z",
      user_id: "u1",
      user_info: { name: "Ada" },
    });

    const result = await verifyChannelWebhookRequest(req, secret);
    expect(result).toEqual({
      valid: true,
      event: {
        event: "member:added",
        channel: "presence-lobby",
        timestamp: "2026-01-01T00:00:00Z",
        userId: "u1",
        userInfo: { name: "Ada" },
      },
    });
  });

  it("rejects a bad signature", async () => {
    const req = signedRequest(
      { event: "channel:occupied", channel: "chat", timestamp: "t" },
      Buffer.from("the-wrong-secret-bytes-padding!!")
    );
    const result = await verifyChannelWebhookRequest(req, secret);
    expect(result.valid).toBe(false);
  });

  it("rejects a signature-valid but non-object body", async () => {
    const req = signedRequest(null as unknown as object);
    const result = await verifyChannelWebhookRequest(req, secret);
    expect(result).toEqual({ valid: false, error: "invalid_payload" });
  });

  it("rejects an unknown event type", async () => {
    const req = signedRequest({
      event: "totally:made-up",
      channel: "chat",
      timestamp: "t",
    });
    const result = await verifyChannelWebhookRequest(req, secret);
    expect(result).toEqual({ valid: false, error: "unknown_event" });
  });
});
