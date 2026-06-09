// ─── Next.js (and Web-standard) route helpers for Ricqchet channels ──────────
//
// These helpers use the Web `Request`/`Response` types, which are exactly the
// signature of a Next.js App Router route handler (`export const POST = ...`).
// They work in any Web-standard runtime (Next, Remix, Hono, Deno, …).

import { timingSafeEqual } from "crypto";
import { verifyRequest, type VerifyOptions } from "../verification";

/** The four channel webhook event types Ricqchet delivers. */
const CHANNEL_WEBHOOK_EVENTS = [
  "channel:occupied",
  "channel:vacated",
  "member:added",
  "member:removed",
] as const;

// ─── Channel authorization route ─────────────────────────────────────────────

/** The payload Ricqchet POSTs to your channel auth endpoint. */
export interface ChannelAuthParams {
  /** The channel the user is trying to join (e.g. `private-orders`). */
  channel: string;
  /** The connecting user's (unverified, client-supplied) id. */
  userId: string;
  /** The connection's socket id. */
  socketId: string;
}

/**
 * What your authorizer returns:
 * - `false` → deny (`403`).
 * - `true` → allow, keeping the client-supplied (unverified) identity.
 * - an object → allow **and bind a verified identity**. Ricqchet overrides the
 *   client-supplied `user_id`/`user_info` with what you return — the secure
 *   pattern for presence and client-event attribution.
 */
export type ChannelAuthResult =
  | boolean
  | { userId?: string; userInfo?: Record<string, unknown> };

/** Decides whether a user may join a channel, given the request. */
export type ChannelAuthorizer = (
  params: ChannelAuthParams,
  request: Request
) => ChannelAuthResult | Promise<ChannelAuthResult>;

/** Options for {@link createChannelAuthRoute}. */
export interface CreateChannelAuthRouteOptions {
  /**
   * Optional shared secret. Ricqchet sends the auth request **unsigned**, so to
   * authenticate the caller, embed the secret in the `channels_auth_endpoint`
   * URL you configure (e.g. `https://app.example.com/api/ricqchet/auth?secret=…`)
   * — or send it as the `x-ricqchet-auth-secret` header via a proxy. When set,
   * requests without a matching secret are rejected with `403`.
   */
  secret?: string;
  /** Query-param name carrying the {@link secret} (default: `"secret"`). */
  secretParam?: string;
}

/**
 * Builds a route handler for Ricqchet's private/presence channel authorization.
 *
 * Unlike Pusher, this is an **inbound allow/deny** endpoint — you do not sign a
 * token. Ricqchet POSTs `{ channel, user_id, socket_id }` and trusts your HTTP
 * status: `200` allows, anything else denies. Respond quickly (Ricqchet times
 * out at ~5s and fails closed).
 *
 * @example
 * ```typescript
 * // app/api/ricqchet/channel-auth/route.ts
 * export const POST = createChannelAuthRoute(async ({ channel, userId }) => {
 *   const session = await getSession();
 *   if (!session || !canAccess(session, channel)) return false;      // 403
 *   return { userId: session.user.id, userInfo: { name: session.user.name } }; // 200 + verified identity
 * });
 * ```
 */
export function createChannelAuthRoute(
  authorize: ChannelAuthorizer,
  options: CreateChannelAuthRouteOptions = {}
): (request: Request) => Promise<Response> {
  const secretParam = options.secretParam ?? "secret";

  return async (request: Request): Promise<Response> => {
    if (
      options.secret &&
      !hasValidSecret(request, options.secret, secretParam)
    ) {
      return json({ error: "forbidden", message: "Invalid auth secret" }, 403);
    }

    const params = await parseAuthParams(request);
    if (!params) {
      return json(
        {
          error: "bad_request",
          message: "Expected JSON body with channel, user_id, socket_id",
        },
        400
      );
    }

    let result: ChannelAuthResult;
    try {
      result = await authorize(params, request);
    } catch {
      // Fail closed on authorizer errors, but distinctly from a deny.
      return json(
        { error: "internal_error", message: "Authorization failed" },
        500
      );
    }

    if (result === false) {
      return json(
        { error: "forbidden", message: "Not permitted to join this channel" },
        403
      );
    }

    if (result === true) {
      return json({}, 200);
    }

    // Bind verified identity.
    const body: Record<string, unknown> = {};
    if (result.userId != null) body.user_id = result.userId;
    if (result.userInfo != null) body.user_info = result.userInfo;
    return json(body, 200);
  };
}

// ─── Channel webhook verification ────────────────────────────────────────────

/** The kinds of server-to-server channel webhook Ricqchet delivers. */
export type ChannelWebhookEventType =
  | "channel:occupied"
  | "channel:vacated"
  | "member:added"
  | "member:removed";

/** A verified channel webhook payload. */
export interface ChannelWebhookEvent {
  event: ChannelWebhookEventType;
  channel: string;
  /** ISO-8601 timestamp the event occurred. */
  timestamp: string;
  /** Present for `member:added` / `member:removed`. */
  userId?: string;
  /** Present for presence members. */
  userInfo?: Record<string, unknown>;
}

/** Result of {@link verifyChannelWebhookRequest}. */
export type ChannelWebhookResult =
  | { valid: true; event: ChannelWebhookEvent }
  | { valid: false; error: string };

/**
 * Verifies a Ricqchet channel webhook (`channel:occupied`, `channel:vacated`,
 * `member:added`, `member:removed`) delivered to your `channels_webhook_url`,
 * and returns the typed payload. Uses the same `X-Ricqchet-Signature` HMAC as
 * message webhooks — verify with your tenant signing secret.
 *
 * @example
 * ```typescript
 * export async function POST(request: Request) {
 *   const result = await verifyChannelWebhookRequest(request, signingSecret);
 *   if (!result.valid) return new Response(result.error, { status: 401 });
 *   if (result.event.event === "member:added") track(result.event.userId);
 *   return new Response("ok");
 * }
 * ```
 */
export async function verifyChannelWebhookRequest(
  request: Request,
  signingSecret: Uint8Array | Buffer,
  options?: VerifyOptions
): Promise<ChannelWebhookResult> {
  const rawBody = await request.text();
  const headers = Object.fromEntries(request.headers.entries());

  const verification = verifyRequest(headers, rawBody, signingSecret, options);
  if (!verification.valid) {
    return { valid: false, error: verification.error };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(rawBody);
  } catch {
    return { valid: false, error: "invalid_json" };
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { valid: false, error: "invalid_payload" };
  }

  const obj = parsed as Record<string, unknown>;
  if (!isKnownWebhookEvent(obj.event)) {
    return { valid: false, error: "unknown_event" };
  }
  if (typeof obj.channel !== "string" || typeof obj.timestamp !== "string") {
    return { valid: false, error: "invalid_payload" };
  }

  const event: ChannelWebhookEvent = {
    event: obj.event,
    channel: obj.channel,
    timestamp: obj.timestamp,
  };
  if (typeof obj.user_id === "string") event.userId = obj.user_id;
  if (obj.user_info != null && typeof obj.user_info === "object") {
    event.userInfo = obj.user_info as Record<string, unknown>;
  }

  return { valid: true, event };
}

function isKnownWebhookEvent(value: unknown): value is ChannelWebhookEventType {
  return (
    typeof value === "string" &&
    (CHANNEL_WEBHOOK_EVENTS as readonly string[]).includes(value)
  );
}

// ─── Internal helpers ────────────────────────────────────────────────────────

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function hasValidSecret(
  request: Request,
  secret: string,
  param: string
): boolean {
  const headerSecret = request.headers.get("x-ricqchet-auth-secret");
  if (headerSecret && constantTimeEqual(headerSecret, secret)) return true;
  try {
    const querySecret = new URL(request.url).searchParams.get(param);
    return querySecret != null && constantTimeEqual(querySecret, secret);
  } catch {
    return false;
  }
}

/** Length-guarded constant-time string comparison (avoids timing side-channels). */
function constantTimeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  if (ab.length !== bb.length) return false;
  return timingSafeEqual(ab, bb);
}

async function parseAuthParams(
  request: Request
): Promise<ChannelAuthParams | null> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return null;
  }
  if (!body || typeof body !== "object") return null;

  const { channel, user_id, socket_id } = body as Record<string, unknown>;
  if (typeof channel !== "string" || channel === "") return null;

  return {
    channel,
    userId: typeof user_id === "string" ? user_id : "",
    socketId: typeof socket_id === "string" ? socket_id : "",
  };
}
