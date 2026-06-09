import { describe, it, expect } from "vitest";
import { validateChannelName, channelType } from "../src/channels";

describe("validateChannelName", () => {
  it("accepts simple names", () => {
    expect(validateChannelName("chat-room")).toEqual({ valid: true });
    expect(validateChannelName("private-order-123")).toEqual({ valid: true });
    expect(validateChannelName("presence-lobby")).toEqual({ valid: true });
  });

  it("accepts hierarchical dotted names (backend #127)", () => {
    expect(validateChannelName("orders.us.west")).toEqual({ valid: true });
  });

  it("rejects names containing a colon", () => {
    const result = validateChannelName("channels:app:1:x");
    expect(result.valid).toBe(false);
  });

  it("rejects the reserved name 'phoenix'", () => {
    const result = validateChannelName("phoenix");
    expect(result).toEqual({
      valid: false,
      reason: 'invalid channel name: "phoenix" is reserved',
    });
  });

  it("rejects dot-only names (no alphanumeric)", () => {
    expect(validateChannelName(".").valid).toBe(false);
    expect(validateChannelName("..").valid).toBe(false);
    expect(validateChannelName("--").valid).toBe(false);
  });

  it("rejects empty and over-long names", () => {
    expect(validateChannelName("").valid).toBe(false);
    expect(validateChannelName("a".repeat(165)).valid).toBe(false);
    expect(validateChannelName("a".repeat(164)).valid).toBe(true);
  });

  it("rejects spaces and other disallowed characters", () => {
    expect(validateChannelName("has space").valid).toBe(false);
    expect(validateChannelName("emoji-😀").valid).toBe(false);
  });
});

describe("channelType", () => {
  it("derives type from the name prefix", () => {
    expect(channelType("chat")).toBe("public");
    expect(channelType("private-orders")).toBe("private");
    expect(channelType("presence-lobby")).toBe("presence");
  });
});
