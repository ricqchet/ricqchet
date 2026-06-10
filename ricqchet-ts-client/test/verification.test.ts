import { describe, it, expect } from "vitest";
import { createHmac, randomBytes } from "crypto";
import { verifySignature, verifyRequest } from "../src/verification";

const signingSecret = randomBytes(32);

function sign(
  payload: string,
  secret: Buffer = signingSecret,
  timestamp?: number
): string {
  const ts = timestamp ?? Math.floor(Date.now() / 1000);
  const signedPayload = `${ts}.${payload}`;
  const signature = createHmac("sha256", secret)
    .update(signedPayload)
    .digest("hex");
  return `t=${ts},v1=${signature}`;
}

describe("verifySignature", () => {
  it("verifies valid signature", () => {
    const payload = '{"event": "test"}';
    const timestamp = Math.floor(Date.now() / 1000);
    const signature = sign(payload, signingSecret, timestamp);

    const result = verifySignature(signature, payload, signingSecret);

    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.metadata.timestamp).toBe(timestamp);
    }
  });

  it("returns error for missing signature", () => {
    const result = verifySignature(undefined, "payload", signingSecret);

    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toBe("missing_signature");
    }
  });

  it("returns error for invalid format", () => {
    const result = verifySignature("invalid", "payload", signingSecret);

    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toBe("invalid_format");
    }
  });

  it("returns error for invalid signature", () => {
    const timestamp = Math.floor(Date.now() / 1000);
    const signature = `t=${timestamp},v1=${"0".repeat(64)}`;

    const result = verifySignature(signature, "payload", signingSecret);

    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toBe("invalid_signature");
    }
  });

  it("returns error for expired signature", () => {
    const payload = '{"event": "test"}';
    const oldTimestamp = Math.floor(Date.now() / 1000) - 600;
    const signature = sign(payload, signingSecret, oldTimestamp);

    const result = verifySignature(signature, payload, signingSecret, {
      maxAge: 300,
    });

    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toBe("signature_expired");
    }
  });

  it("allows expired signature when maxAge is null", () => {
    const payload = '{"event": "test"}';
    const oldTimestamp = Math.floor(Date.now() / 1000) - 600;
    const signature = sign(payload, signingSecret, oldTimestamp);

    const result = verifySignature(signature, payload, signingSecret, {
      maxAge: null,
    });

    expect(result.valid).toBe(true);
  });

  it("returns error for modified payload", () => {
    const payload = '{"event": "test"}';
    const signature = sign(payload);

    const result = verifySignature(signature, "modified", signingSecret);

    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toBe("invalid_signature");
    }
  });

  it("returns error for wrong secret", () => {
    const payload = '{"event": "test"}';
    const signature = sign(payload);
    const otherSecret = randomBytes(32);

    const result = verifySignature(signature, payload, otherSecret);

    expect(result.valid).toBe(false);
    if (!result.valid) {
      expect(result.error).toBe("invalid_signature");
    }
  });

  it("handles Buffer payload", () => {
    const payload = Buffer.from('{"event": "test"}');
    const timestamp = Math.floor(Date.now() / 1000);
    const signature = sign(payload.toString("utf-8"), signingSecret, timestamp);

    const result = verifySignature(signature, payload, signingSecret);

    expect(result.valid).toBe(true);
  });
});

describe("verifyRequest", () => {
  it("extracts metadata from headers", () => {
    const payload = '{"event": "test"}';
    const timestamp = Math.floor(Date.now() / 1000);
    const signature = sign(payload, signingSecret, timestamp);

    const headers = {
      "x-ricqchet-signature": signature,
      "x-ricqchet-message-id": "msg-123",
      "x-ricqchet-attempt": "2",
    };

    const result = verifyRequest(headers, payload, signingSecret);

    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.metadata.messageId).toBe("msg-123");
      expect(result.metadata.attempt).toBe(2);
      expect(result.metadata.batchId).toBe(null);
    }
  });

  it("extracts batch metadata", () => {
    const payload = '{"event": "test"}';
    const timestamp = Math.floor(Date.now() / 1000);
    const signature = sign(payload, signingSecret, timestamp);

    const headers = {
      "x-ricqchet-signature": signature,
      "x-ricqchet-batch-id": "batch-456",
      "x-ricqchet-attempt": "1",
    };

    const result = verifyRequest(headers, payload, signingSecret);

    expect(result.valid).toBe(true);
    if (result.valid) {
      expect(result.metadata.batchId).toBe("batch-456");
      expect(result.metadata.messageId).toBe(null);
    }
  });

  it("handles case-insensitive headers", () => {
    const payload = '{"event": "test"}';
    const timestamp = Math.floor(Date.now() / 1000);
    const signature = sign(payload, signingSecret, timestamp);

    const headers = {
      "X-Ricqchet-Signature": signature,
      "X-Ricqchet-Message-Id": "msg-123",
    };

    const result = verifyRequest(headers, payload, signingSecret);

    expect(result.valid).toBe(true);
  });
});
