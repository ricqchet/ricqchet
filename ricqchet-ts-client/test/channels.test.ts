import { describe, it, expect, beforeAll, afterAll, afterEach } from "vitest";
import { setupServer } from "msw/node";
import { http, HttpResponse } from "msw";
import { RicqchetClient } from "../src/client";
import { RicqchetError } from "../src/error";

const baseUrl = "http://localhost:3000";
const apiKey = "test_api_key";

const server = setupServer();

beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe("RicqchetClient — Channels", () => {
  describe("triggerEvent", () => {
    it("triggers an event on a single channel", async () => {
      server.use(
        http.post(`${baseUrl}/v1/channels/events`, async ({ request }) => {
          expect(request.headers.get("authorization")).toBe(`Bearer ${apiKey}`);
          const body = (await request.json()) as Record<string, unknown>;
          expect(body.channel).toBe("my-channel");
          expect(body.event).toBe("user.joined");
          expect(body.data).toEqual({ name: "Alice" });

          return HttpResponse.json(
            { event_ids: ["evt-1"], channel: "my-channel" },
            { status: 202 }
          );
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const result = await client.triggerEvent({
        channel: "my-channel",
        event: "user.joined",
        data: { name: "Alice" },
      });

      expect(result.eventIds).toEqual(["evt-1"]);
      expect(result.channel).toBe("my-channel");
    });

    it("triggers an event on multiple channels", async () => {
      server.use(
        http.post(`${baseUrl}/v1/channels/events`, async ({ request }) => {
          const body = (await request.json()) as Record<string, unknown>;
          expect(body.channels).toEqual(["ch-1", "ch-2"]);

          return HttpResponse.json(
            { event_ids: ["evt-1", "evt-2"], channels: ["ch-1", "ch-2"] },
            { status: 202 }
          );
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const result = await client.triggerEvent({
        channels: ["ch-1", "ch-2"],
        event: "update",
      });

      expect(result.eventIds).toEqual(["evt-1", "evt-2"]);
      expect(result.channels).toEqual(["ch-1", "ch-2"]);
    });

    it("includes socket_id for echo suppression", async () => {
      server.use(
        http.post(`${baseUrl}/v1/channels/events`, async ({ request }) => {
          const body = (await request.json()) as Record<string, unknown>;
          expect(body.socket_id).toBe("sock-123");

          return HttpResponse.json(
            { event_ids: ["evt-1"], channel: "ch" },
            { status: 202 }
          );
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      await client.triggerEvent({
        channel: "ch",
        event: "ping",
        socketId: "sock-123",
      });
    });

    it("throws on validation error", async () => {
      server.use(
        http.post(`${baseUrl}/v1/channels/events`, () =>
          HttpResponse.json(
            { error: "validation_error", message: "event is required" },
            { status: 422 }
          )
        )
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      await expect(client.triggerEvent({ event: "" })).rejects.toThrow(
        RicqchetError
      );
    });
  });

  describe("triggerBatchEvents", () => {
    it("triggers a batch of events", async () => {
      server.use(
        http.post(
          `${baseUrl}/v1/channels/events/batch`,
          async ({ request }) => {
            const body = (await request.json()) as Record<string, unknown>;
            expect((body.batch as unknown[]).length).toBe(2);

            return HttpResponse.json(
              {
                results: [
                  {
                    channel: "ch-1",
                    event: "e1",
                    event_id: "evt-1",
                    status: "ok",
                    error: null,
                  },
                  {
                    channel: "ch-2",
                    event: "e2",
                    event_id: null,
                    status: "error",
                    error: "channel not found",
                  },
                ],
              },
              { status: 202 }
            );
          }
        )
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const result = await client.triggerBatchEvents({
        batch: [
          { channel: "ch-1", event: "e1", data: { x: 1 } },
          { channel: "ch-2", event: "e2" },
        ],
      });

      expect(result.results).toHaveLength(2);
      expect(result.results[0].status).toBe("ok");
      expect(result.results[0].eventId).toBe("evt-1");
      expect(result.results[1].status).toBe("error");
      expect(result.results[1].error).toBe("channel not found");
    });
  });

  describe("listChannels", () => {
    it("lists active channels", async () => {
      server.use(
        http.get(`${baseUrl}/v1/channels`, () =>
          HttpResponse.json({
            channels: [
              { name: "public-chat", subscriber_count: 5, type: "public" },
              {
                name: "presence-lobby",
                subscriber_count: 2,
                type: "presence",
              },
            ],
          })
        )
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const channels = await client.listChannels();

      expect(channels).toHaveLength(2);
      expect(channels[0].name).toBe("public-chat");
      expect(channels[0].subscriberCount).toBe(5);
      expect(channels[1].type).toBe("presence");
    });
  });

  describe("getChannel", () => {
    it("gets channel info with presence members", async () => {
      server.use(
        http.get(`${baseUrl}/v1/channels/presence-lobby`, () =>
          HttpResponse.json({
            name: "presence-lobby",
            type: "presence",
            subscriber_count: 2,
            occupied: true,
            members: [
              {
                user_id: "user-1",
                user_info: { name: "Alice" },
                joined_at: "2024-01-01T00:00:00Z",
              },
            ],
          })
        )
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const info = await client.getChannel("presence-lobby");

      expect(info.occupied).toBe(true);
      expect(info.members).toHaveLength(1);
      expect(info.members![0].userId).toBe("user-1");
      expect(info.members![0].userInfo).toEqual({ name: "Alice" });
    });

    it("returns null members for non-presence channel", async () => {
      server.use(
        http.get(`${baseUrl}/v1/channels/public-chat`, () =>
          HttpResponse.json({
            name: "public-chat",
            type: "public",
            subscriber_count: 10,
            occupied: true,
            members: null,
          })
        )
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const info = await client.getChannel("public-chat");
      expect(info.members).toBeNull();
    });
  });

  describe("getChannelEvents", () => {
    it("gets event history", async () => {
      server.use(
        http.get(`${baseUrl}/v1/channels/my-channel/events`, () =>
          HttpResponse.json({
            events: [
              {
                id: "evt-1",
                channel: "my-channel",
                event: "message",
                data: { text: "hi" },
                sequence: 1,
                inserted_at: "2024-01-01T00:00:00Z",
              },
            ],
          })
        )
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const events = await client.getChannelEvents("my-channel");

      expect(events).toHaveLength(1);
      expect(events[0].event).toBe("message");
      expect(events[0].insertedAt).toBe("2024-01-01T00:00:00Z");
    });

    it("passes since_id and limit query params", async () => {
      server.use(
        http.get(`${baseUrl}/v1/channels/ch/events`, ({ request }) => {
          const url = new URL(request.url);
          expect(url.searchParams.get("since_id")).toBe("evt-5");
          expect(url.searchParams.get("limit")).toBe("10");

          return HttpResponse.json({ events: [] });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      await client.getChannelEvents("ch", { sinceId: "evt-5", limit: 10 });
    });
  });

  describe("getChannelMembers", () => {
    it("lists presence members", async () => {
      server.use(
        http.get(`${baseUrl}/v1/channels/presence-room/members`, () =>
          HttpResponse.json({
            members: [
              {
                user_id: "u1",
                user_info: null,
                joined_at: "2024-01-01T00:00:00Z",
              },
            ],
          })
        )
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const members = await client.getChannelMembers("presence-room");

      expect(members).toHaveLength(1);
      expect(members[0].userId).toBe("u1");
      expect(members[0].userInfo).toBeNull();
    });
  });

  describe("disconnectUser", () => {
    it("disconnects a user from all channels", async () => {
      server.use(
        http.delete(`${baseUrl}/v1/channels/users/user-123/connections`, () =>
          HttpResponse.json({ status: "ok", user_id: "user-123" })
        )
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const result = await client.disconnectUser("user-123");

      expect(result.status).toBe("ok");
      expect(result.userId).toBe("user-123");
    });
  });
});
