import { RicqchetError } from "./error";
import { HttpClient } from "./http";
import type {
  TriggerEventParams,
  TriggerEventResult,
  BatchTriggerParams,
  BatchTriggerResult,
  Channel,
  ChannelInfo,
  ChannelEvent,
  PresenceMember,
  DisconnectResult,
} from "./types";

/**
 * Maximum number of destinations allowed in a single fan-out request.
 * Mirrors the server-side limit so the client can fail fast.
 */
const MAX_FAN_OUT_DESTINATIONS = 100;

/**
 * Configuration options for the Ricqchet client.
 */
export interface RicqchetClientOptions {
  /** The base URL of your Ricqchet server */
  baseUrl: string;
  /** Your API key for authentication */
  apiKey: string;
  /** HTTP timeout in milliseconds (default: 30000) */
  timeout?: number;
}

/**
 * Options for publishing a message.
 */
export interface PublishOptions {
  /** Delay delivery (e.g., "30s", "5m", "1h") */
  delay?: string;
  /** Deduplication key */
  dedupKey?: string;
  /** Deduplication TTL in seconds (default: 300) */
  dedupTtl?: number;
  /** Max retry attempts (default: 3) */
  retries?: number;
  /** Batch key for grouping messages */
  batchKey?: string;
  /** Max batch size (1-1000) */
  batchSize?: number;
  /** Batch timeout in seconds */
  batchTimeout?: number;
  /** Headers to forward to destination */
  forwardHeaders?: Record<string, string>;
  /** Content-Type header (default: "application/json") */
  contentType?: string;
}

/**
 * Result of a successful publish operation.
 */
export interface PublishResult {
  messageId: string;
}

/**
 * Result of a successful fan-out operation.
 */
export interface FanOutResult {
  messageIds: string[];
}

/**
 * Service health status returned by {@link RicqchetClient.health}.
 */
export interface HealthStatus {
  /** Service status — `"ok"` when the server is healthy */
  status: string;
}

/**
 * Message status and details.
 */
export interface Message {
  id: string;
  status: "pending" | "dispatched" | "delivered" | "failed";
  destinationUrl: string;
  method: string;
  attempts: number;
  maxRetries: number;
  createdAt: string;
  scheduledAt: string | null;
  dispatchedAt: string | null;
  completedAt: string | null;
  lastError: string | null;
  lastResponseStatus: number | null;
}

/**
 * Ricqchet HTTP client for publishing messages, managing deliveries, and
 * interacting with real-time channels.
 *
 * @example
 * ```typescript
 * const client = new RicqchetClient({
 *   baseUrl: 'https://your-ricqchet.fly.dev',
 *   apiKey: process.env.RICQCHET_API_KEY!
 * });
 *
 * const { messageId } = await client.publish(
 *   'https://myapp.com/webhook',
 *   { event: 'order.created', id: 123 }
 * );
 * ```
 */
export class RicqchetClient {
  private http: HttpClient;
  private apiKey: string;

  constructor(options: RicqchetClientOptions) {
    this.http = new HttpClient(options.baseUrl, options.timeout ?? 30000);
    this.apiKey = options.apiKey;
  }

  // ─── Service ─────────────────────────────────────────────────────────────

  /**
   * Checks whether the Ricqchet server is healthy.
   *
   * This endpoint is public and requires no authentication, so it works even
   * before an API key is provisioned — useful for readiness probes against a
   * self-hosted instance.
   *
   * @returns The server health status (`{ status: "ok" }` when healthy)
   *
   * @example
   * ```typescript
   * const { status } = await client.health();
   * if (status !== "ok") throw new Error("Ricqchet is unhealthy");
   * ```
   */
  async health(): Promise<HealthStatus> {
    // No `auth` is passed: /health is the one unauthenticated relay route.
    const response = await this.http.request("GET", "/health", {
      headers: {},
      body: null,
    });

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return { status: data.status };
  }

  // ─── Publishing ──────────────────────────────────────────────────────────

  /**
   * Publishes a message to a destination URL.
   *
   * @param destination - The URL to deliver the message to
   * @param payload - The message payload (will be JSON-encoded if object)
   * @param options - Optional publish configuration
   * @returns The message ID
   *
   * @example
   * ```typescript
   * const { messageId } = await client.publish(
   *   'https://api.example.com/webhook',
   *   { event: 'user.created' },
   *   { delay: '5m' }
   * );
   * ```
   */
  async publish(
    destination: string,
    payload: unknown,
    options?: PublishOptions
  ): Promise<PublishResult> {
    const headers = this.buildPublishHeaders(destination, options);
    const body =
      typeof payload === "string" ? payload : JSON.stringify(payload);

    const response = await this.request("POST", "/v1/publish", headers, body);

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return { messageId: data.message_id };
  }

  /**
   * Publishes a message to multiple destinations (fan-out).
   *
   * @param destinations - Array of URLs to deliver the message to
   * @param payload - The message payload
   * @param options - Optional publish configuration
   * @returns Array of message IDs
   *
   * @example
   * ```typescript
   * const { messageIds } = await client.publishFanOut(
   *   ['https://a.example.com', 'https://b.example.com'],
   *   { event: 'broadcast' }
   * );
   * ```
   */
  async publishFanOut(
    destinations: string[],
    payload: unknown,
    options?: PublishOptions
  ): Promise<FanOutResult> {
    if (destinations.length === 0) {
      throw new RicqchetError(
        "validation_error",
        "publishFanOut requires at least one destination"
      );
    }

    if (destinations.length > MAX_FAN_OUT_DESTINATIONS) {
      throw new RicqchetError(
        "validation_error",
        `publishFanOut supports at most ${MAX_FAN_OUT_DESTINATIONS} destinations (received ${destinations.length})`
      );
    }

    const headers: Record<string, string> = {
      "ricqchet-fan-out": destinations.join(", "),
      ...this.buildCommonHeaders(options),
    };

    const body =
      typeof payload === "string" ? payload : JSON.stringify(payload);

    const response = await this.request("POST", "/v1/publish", headers, body);

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return { messageIds: data.message_ids };
  }

  // ─── Messages ────────────────────────────────────────────────────────────

  /**
   * Gets the status and details of a message.
   *
   * @param messageId - The message ID to look up
   * @returns The message details
   *
   * @example
   * ```typescript
   * const message = await client.getMessage('550e8400-...');
   * console.log(message.status); // 'delivered'
   * ```
   */
  async getMessage(messageId: string): Promise<Message> {
    const response = await this.request(
      "GET",
      `/v1/messages/${messageId}`,
      {},
      null
    );

    if (response.status === 404) {
      throw new RicqchetError("not_found", "Message not found", 404);
    }

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return this.mapMessage(data);
  }

  /**
   * Cancels a pending message.
   *
   * @param messageId - The message ID to cancel
   * @returns Confirmation of cancellation
   * @throws {RicqchetError} If the message has already been dispatched
   *
   * @example
   * ```typescript
   * const { cancelled } = await client.cancelMessage('550e8400-...');
   * ```
   */
  async cancelMessage(messageId: string): Promise<{ cancelled: boolean }> {
    const response = await this.request(
      "DELETE",
      `/v1/messages/${messageId}`,
      {},
      null
    );

    if (response.status === 404) {
      throw new RicqchetError("not_found", "Message not found", 404);
    }

    if (response.status === 409) {
      throw new RicqchetError(
        "conflict",
        "Message has already been dispatched",
        409
      );
    }

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return { cancelled: data.cancelled };
  }

  /**
   * Retrieves the signing secret for webhook verification.
   *
   * @returns The binary signing secret
   *
   * @example
   * ```typescript
   * const signingSecret = await client.getSigningSecret();
   * ```
   */
  async getSigningSecret(): Promise<Uint8Array> {
    const response = await this.request("GET", "/v1/signing-secret", {}, null);

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return Buffer.from(data.signing_secret, "base64");
  }

  // ─── Channels ────────────────────────────────────────────────────────────

  /**
   * Triggers an event on one or more channels.
   *
   * @param params - Event parameters including channel(s), event name, and optional data
   * @returns Event IDs and channel information
   */
  async triggerEvent(params: TriggerEventParams): Promise<TriggerEventResult> {
    const body: Record<string, unknown> = { event: params.event };
    if (params.channel != null) body.channel = params.channel;
    if (params.channels != null) body.channels = params.channels;
    if (params.data !== undefined) body.data = params.data;
    if (params.socketId != null) body.socket_id = params.socketId;

    const response = await this.request(
      "POST",
      "/v1/channels/events",
      {},
      JSON.stringify(body)
    );

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    const result: TriggerEventResult = { eventIds: data.event_ids };
    if (data.channel) result.channel = data.channel;
    if (data.channels) result.channels = data.channels;
    return result;
  }

  /**
   * Triggers multiple events in a single batch request.
   *
   * @param params - Batch of events (up to 100)
   * @returns Results for each event in the batch
   */
  async triggerBatchEvents(
    params: BatchTriggerParams
  ): Promise<BatchTriggerResult> {
    const body = {
      batch: params.batch.map((item) => {
        const mapped: Record<string, unknown> = {
          channel: item.channel,
          event: item.event,
        };
        if (item.data !== undefined) mapped.data = item.data;
        if (item.socketId != null) mapped.socket_id = item.socketId;
        return mapped;
      }),
    };

    const response = await this.request(
      "POST",
      "/v1/channels/events/batch",
      {},
      JSON.stringify(body)
    );

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return {
      results: data.results.map((r: Record<string, unknown>) => ({
        channel: r.channel as string,
        event: r.event as string,
        eventId: (r.event_id as string) ?? null,
        status: r.status as "ok" | "error",
        error: (r.error as string) ?? null,
      })),
    };
  }

  /**
   * Lists all active channels.
   *
   * @returns Array of active channels with subscriber counts
   */
  async listChannels(): Promise<Channel[]> {
    const response = await this.request("GET", "/v1/channels", {}, null);

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return data.channels.map((c: Record<string, unknown>) => ({
      name: c.name as string,
      subscriberCount: c.subscriber_count as number,
      type: c.type as Channel["type"],
    }));
  }

  /**
   * Gets detailed information about a specific channel.
   *
   * @param channelName - The channel name
   * @returns Channel info including subscriber count and presence members (if applicable)
   */
  async getChannel(channelName: string): Promise<ChannelInfo> {
    const response = await this.request(
      "GET",
      `/v1/channels/${encodeURIComponent(channelName)}`,
      {},
      null
    );

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return {
      name: data.name,
      type: data.type,
      subscriberCount: data.subscriber_count,
      occupied: data.occupied,
      members: data.members ? data.members.map(this.mapPresenceMember) : null,
    };
  }

  /**
   * Gets event history for a channel.
   *
   * @param channelName - The channel name
   * @param options - Optional filter parameters
   * @returns Array of channel events
   */
  async getChannelEvents(
    channelName: string,
    options?: { sinceId?: string; limit?: number }
  ): Promise<ChannelEvent[]> {
    const params: string[] = [];
    if (options?.sinceId)
      params.push(`since_id=${encodeURIComponent(options.sinceId)}`);
    if (options?.limit != null) params.push(`limit=${options.limit}`);
    const qs = params.length > 0 ? `?${params.join("&")}` : "";

    const response = await this.request(
      "GET",
      `/v1/channels/${encodeURIComponent(channelName)}/events${qs}`,
      {},
      null
    );

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return data.events.map((e: Record<string, unknown>) => ({
      id: e.id as string,
      channel: e.channel as string,
      event: e.event as string,
      data: e.data,
      sequence: e.sequence as number,
      insertedAt: e.inserted_at as string,
    }));
  }

  /**
   * Lists members of a presence channel.
   *
   * @param channelName - The presence channel name (must start with "presence-")
   * @returns Array of presence members
   */
  async getChannelMembers(channelName: string): Promise<PresenceMember[]> {
    const response = await this.request(
      "GET",
      `/v1/channels/${encodeURIComponent(channelName)}/members`,
      {},
      null
    );

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return data.members.map(this.mapPresenceMember);
  }

  /**
   * Disconnects a user from all channels.
   *
   * @param userId - The user ID to disconnect
   * @returns Disconnect confirmation
   */
  async disconnectUser(userId: string): Promise<DisconnectResult> {
    const response = await this.request(
      "DELETE",
      `/v1/channels/users/${encodeURIComponent(userId)}/connections`,
      {},
      null
    );

    if (!response.ok) {
      throw await this.http.parseError(response);
    }

    const data = await response.json();
    return { status: data.status, userId: data.user_id };
  }

  // ─── Private Helpers ─────────────────────────────────────────────────────

  private async request(
    method: string,
    path: string,
    headers: Record<string, string>,
    body: string | null
  ): Promise<Response> {
    return this.http.request(method, path, {
      headers,
      body,
      auth: { type: "bearer", token: this.apiKey },
    });
  }

  private buildPublishHeaders(
    destination: string,
    options?: PublishOptions
  ): Record<string, string> {
    return {
      "ricqchet-destination": destination,
      ...this.buildCommonHeaders(options),
    };
  }

  private buildCommonHeaders(options?: PublishOptions): Record<string, string> {
    const headers: Record<string, string> = {};

    if (options?.delay) headers["ricqchet-delay"] = options.delay;
    if (options?.dedupKey) headers["ricqchet-dedup-key"] = options.dedupKey;
    if (options?.dedupTtl)
      headers["ricqchet-dedup-ttl"] = options.dedupTtl.toString();
    if (options?.retries)
      headers["ricqchet-retries"] = options.retries.toString();
    if (options?.batchKey) headers["ricqchet-batch-key"] = options.batchKey;
    if (options?.batchSize)
      headers["ricqchet-batch-size"] = options.batchSize.toString();
    if (options?.batchTimeout)
      headers["ricqchet-batch-timeout"] = options.batchTimeout.toString();
    if (options?.contentType) headers["content-type"] = options.contentType;

    if (options?.forwardHeaders) {
      for (const [key, value] of Object.entries(options.forwardHeaders)) {
        headers[`ricqchet-forward-${key}`] = value;
      }
    }

    return headers;
  }

  private mapMessage(data: Record<string, unknown>): Message {
    return {
      id: data.id as string,
      status: data.status as Message["status"],
      destinationUrl: data.destination_url as string,
      method: data.method as string,
      attempts: data.attempts as number,
      maxRetries: data.max_retries as number,
      createdAt: data.created_at as string,
      scheduledAt: data.scheduled_at as string | null,
      dispatchedAt: data.dispatched_at as string | null,
      completedAt: data.completed_at as string | null,
      lastError: data.last_error as string | null,
      lastResponseStatus: data.last_response_status as number | null,
    };
  }

  private mapPresenceMember(m: Record<string, unknown>): PresenceMember {
    return {
      userId: m.user_id as string,
      userInfo: (m.user_info as Record<string, unknown>) ?? null,
      joinedAt: m.joined_at as string,
    };
  }
}
