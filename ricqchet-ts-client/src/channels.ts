// ─── Channel Name Validation ─────────────────────────────────────────────────
//
// Mirrors the server-side rules in Ricqchet.Channels.validate_channel_name so
// invalid names fail fast on the client instead of after a WebSocket round-trip.
// As of backend #127 ("simplify channels to bare topic names"), names may
// contain dots for hierarchical names (e.g. "orders.us.west") but never ":".

/** A channel's type, derived from its name prefix. */
export type ChannelType = "public" | "private" | "presence";

/** Result of {@link validateChannelName}. */
export type ChannelNameValidation =
  | { valid: true }
  | { valid: false; reason: string };

const CHANNEL_NAME_REGEX = /^[a-zA-Z0-9_.-]{1,164}$/;
const ALPHANUMERIC_REGEX = /[a-zA-Z0-9]/;

// Reserved by the Phoenix socket transport (heartbeats use the "phoenix" topic).
const RESERVED_CHANNEL_NAMES = ["phoenix"];

/**
 * Validates a channel name against the server's rules.
 *
 * Names must be 1–164 characters of letters, digits, `-`, `_`, or `.`, contain
 * at least one alphanumeric character (so `.`/`..` are rejected), and must not
 * be the reserved name `phoenix`. `:` is not permitted.
 *
 * @example
 * ```typescript
 * validateChannelName("orders.us.west"); // { valid: true }
 * validateChannelName("bad:name");       // { valid: false, reason: "..." }
 * ```
 */
export function validateChannelName(name: string): ChannelNameValidation {
  if (typeof name !== "string") {
    return { valid: false, reason: "channel name must be a string" };
  }

  if (!CHANNEL_NAME_REGEX.test(name)) {
    return {
      valid: false,
      reason:
        "invalid channel name: must be 1-164 alphanumeric, dash, underscore, or dot characters",
    };
  }

  if (RESERVED_CHANNEL_NAMES.includes(name)) {
    return {
      valid: false,
      reason: `invalid channel name: "${name}" is reserved`,
    };
  }

  if (!ALPHANUMERIC_REGEX.test(name)) {
    return {
      valid: false,
      reason:
        "invalid channel name: must contain at least one alphanumeric character",
    };
  }

  return { valid: true };
}

/**
 * Returns the {@link ChannelType} implied by a channel name's prefix.
 *
 * `private-*` → `"private"`, `presence-*` → `"presence"`, otherwise `"public"`.
 */
export function channelType(name: string): ChannelType {
  if (name.startsWith("private-")) return "private";
  if (name.startsWith("presence-")) return "presence";
  return "public";
}
