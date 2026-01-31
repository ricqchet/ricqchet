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

describe("RicqchetClient", () => {
  describe("publish", () => {
    it("publishes a message successfully", async () => {
      const messageId = "550e8400-e29b-41d4-a716-446655440000";

      server.use(
        http.post(`${baseUrl}/v1/publish`, async ({ request }) => {
          const auth = request.headers.get("authorization");
          expect(auth).toBe(`Bearer ${apiKey}`);

          const destination = request.headers.get("ricqchet-destination");
          expect(destination).toBe("https://example.com");

          const body = await request.json();
          expect(body).toEqual({ event: "test" });

          return HttpResponse.json({ message_id: messageId });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const result = await client.publish("https://example.com", {
        event: "test",
      });

      expect(result.messageId).toBe(messageId);
    });

    it("includes delay header when provided", async () => {
      server.use(
        http.post(`${baseUrl}/v1/publish`, async ({ request }) => {
          const delay = request.headers.get("ricqchet-delay");
          expect(delay).toBe("5m");

          return HttpResponse.json({ message_id: "test-id" });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      await client.publish(
        "https://example.com",
        { event: "test" },
        { delay: "5m" }
      );
    });

    it("includes dedup headers when provided", async () => {
      server.use(
        http.post(`${baseUrl}/v1/publish`, async ({ request }) => {
          expect(request.headers.get("ricqchet-dedup-key")).toBe("order-123");
          expect(request.headers.get("ricqchet-dedup-ttl")).toBe("3600");

          return HttpResponse.json({ message_id: "test-id" });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      await client.publish(
        "https://example.com",
        { event: "test" },
        { dedupKey: "order-123", dedupTtl: 3600 }
      );
    });

    it("includes forward headers when provided", async () => {
      server.use(
        http.post(`${baseUrl}/v1/publish`, async ({ request }) => {
          expect(request.headers.get("ricqchet-forward-x-custom")).toBe(
            "value"
          );

          return HttpResponse.json({ message_id: "test-id" });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      await client.publish(
        "https://example.com",
        { event: "test" },
        { forwardHeaders: { "x-custom": "value" } }
      );
    });

    it("throws error for 422 response", async () => {
      server.use(
        http.post(`${baseUrl}/v1/publish`, () => {
          return HttpResponse.json(
            { error: "validation_error", message: "Invalid URL" },
            { status: 422 }
          );
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });

      await expect(
        client.publish("invalid", { event: "test" })
      ).rejects.toThrow(RicqchetError);
    });

    it("throws error for 401 response", async () => {
      server.use(
        http.post(`${baseUrl}/v1/publish`, () => {
          return HttpResponse.json({ error: "unauthorized" }, { status: 401 });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });

      await expect(
        client.publish("https://example.com", { event: "test" })
      ).rejects.toThrow(RicqchetError);
    });
  });

  describe("publishFanOut", () => {
    it("publishes to multiple destinations", async () => {
      const messageIds = ["id1", "id2", "id3"];

      server.use(
        http.post(`${baseUrl}/v1/publish`, async ({ request }) => {
          const fanOut = request.headers.get("ricqchet-fan-out");
          expect(fanOut).toContain("https://a.example.com");
          expect(fanOut).toContain("https://b.example.com");

          return HttpResponse.json({ message_ids: messageIds });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const result = await client.publishFanOut(
        ["https://a.example.com", "https://b.example.com"],
        { event: "broadcast" }
      );

      expect(result.messageIds).toEqual(messageIds);
    });
  });

  describe("getMessage", () => {
    it("gets message status", async () => {
      const messageId = "test-message-id";

      server.use(
        http.get(`${baseUrl}/v1/messages/${messageId}`, () => {
          return HttpResponse.json({
            id: messageId,
            status: "delivered",
            destination_url: "https://example.com",
            method: "POST",
            attempts: 1,
            max_retries: 3,
            created_at: "2024-01-01T00:00:00Z",
            scheduled_at: null,
            dispatched_at: "2024-01-01T00:00:01Z",
            completed_at: "2024-01-01T00:00:02Z",
            last_error: null,
            last_response_status: 200,
          });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const message = await client.getMessage(messageId);

      expect(message.id).toBe(messageId);
      expect(message.status).toBe("delivered");
      expect(message.destinationUrl).toBe("https://example.com");
    });

    it("throws not_found error for 404", async () => {
      server.use(
        http.get(`${baseUrl}/v1/messages/unknown`, () => {
          return HttpResponse.json({ error: "not_found" }, { status: 404 });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });

      await expect(client.getMessage("unknown")).rejects.toThrow(RicqchetError);
    });
  });

  describe("cancelMessage", () => {
    it("cancels a pending message", async () => {
      const messageId = "test-message-id";

      server.use(
        http.delete(`${baseUrl}/v1/messages/${messageId}`, () => {
          return HttpResponse.json({ cancelled: true });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const result = await client.cancelMessage(messageId);

      expect(result.cancelled).toBe(true);
    });

    it("throws conflict error for 409", async () => {
      server.use(
        http.delete(`${baseUrl}/v1/messages/test`, () => {
          return HttpResponse.json(
            { error: "already_dispatched" },
            { status: 409 }
          );
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });

      try {
        await client.cancelMessage("test");
        expect.fail("Should have thrown");
      } catch (error) {
        expect(error).toBeInstanceOf(RicqchetError);
        expect((error as RicqchetError).type).toBe("conflict");
      }
    });
  });

  describe("getSigningSecret", () => {
    it("gets the signing secret", async () => {
      const secret = Buffer.from("test-secret-32-bytes-long-here!!");
      const encoded = secret.toString("base64");

      server.use(
        http.get(`${baseUrl}/v1/signing-secret`, () => {
          return HttpResponse.json({ signing_secret: encoded });
        })
      );

      const client = new RicqchetClient({ baseUrl, apiKey });
      const result = await client.getSigningSecret();

      expect(Buffer.from(result).toString()).toBe(secret.toString());
    });
  });
});
