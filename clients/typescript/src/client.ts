import { RicqchetError } from "./error";

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
 * Ricqchet HTTP client for publishing messages and managing deliveries.
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
  private baseUrl: string;
  private apiKey: string;
  private timeout: number;

  constructor(options: RicqchetClientOptions) {
    this.baseUrl = options.baseUrl.replace(/\/$/, "");
    this.apiKey = options.apiKey;
    this.timeout = options.timeout ?? 30000;
  }

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
      throw await this.parseError(response);
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
    const headers: Record<string, string> = {
      "ricqchet-fan-out": destinations.join(", "),
      ...this.buildCommonHeaders(options),
    };

    const body =
      typeof payload === "string" ? payload : JSON.stringify(payload);

    const response = await this.request("POST", "/v1/publish", headers, body);

    if (!response.ok) {
      throw await this.parseError(response);
    }

    const data = await response.json();
    return { messageIds: data.message_ids };
  }

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
      throw await this.parseError(response);
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
      throw await this.parseError(response);
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
      throw await this.parseError(response);
    }

    const data = await response.json();
    return Buffer.from(data.signing_secret, "base64");
  }

  private async request(
    method: string,
    path: string,
    headers: Record<string, string>,
    body: string | null
  ): Promise<Response> {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeout);

    try {
      return await fetch(`${this.baseUrl}${path}`, {
        method,
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          "Content-Type": "application/json",
          "User-Agent": "ricqchet-typescript/0.1.0",
          ...headers,
        },
        body,
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timeoutId);
    }
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

  private async parseError(response: Response): Promise<RicqchetError> {
    try {
      const data = await response.json();
      return RicqchetError.fromResponse(response.status, data);
    } catch {
      return new RicqchetError(
        "unknown_error",
        `Request failed with status ${response.status}`,
        response.status
      );
    }
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
}
