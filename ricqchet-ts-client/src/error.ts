/**
 * Error types returned by the Ricqchet client.
 */
export type RicqchetErrorType =
  | "bad_request"
  | "unauthorized"
  | "forbidden"
  | "not_found"
  | "conflict"
  | "validation_error"
  | "rate_limited"
  | "server_error"
  | "connection_error"
  | "unknown_error";

/**
 * Error class for Ricqchet API errors.
 */
export class RicqchetError extends Error {
  readonly type: RicqchetErrorType;
  readonly status: number | null;
  readonly details: Record<string, unknown> | null;
  /**
   * The server's machine-readable error code (the response body's `error`
   * field), e.g. `"duplicate_message"`, `"already_dispatched"`, or
   * `"rate_limit_exceeded"`. `null` for client-side and connection errors.
   */
  readonly code: string | null;
  /** Seconds to wait before retrying, from the `Retry-After` header on `429`s. */
  readonly retryAfter: number | null;

  constructor(
    type: RicqchetErrorType,
    message: string,
    status: number | null = null,
    details: Record<string, unknown> | null = null,
    retryAfter: number | null = null
  ) {
    super(message);
    this.name = "RicqchetError";
    this.type = type;
    this.status = status;
    this.details = details;
    this.code = typeof details?.error === "string" ? details.error : null;
    this.retryAfter = retryAfter;
  }

  /**
   * Creates an error from an HTTP response.
   */
  static fromResponse(
    status: number,
    body: Record<string, unknown> | null,
    retryAfter: number | null = null
  ): RicqchetError {
    const type = this.typeFromStatus(status);
    const message = this.extractMessage(body);
    return new RicqchetError(type, message, status, body, retryAfter);
  }

  /**
   * Creates a connection error.
   */
  static connectionError(reason: unknown): RicqchetError {
    const message =
      reason instanceof Error
        ? `Connection failed: ${reason.message}`
        : `Connection failed: ${String(reason)}`;
    return new RicqchetError("connection_error", message, null, { reason });
  }

  private static typeFromStatus(status: number): RicqchetErrorType {
    switch (status) {
      case 400:
        return "bad_request";
      case 401:
        return "unauthorized";
      case 403:
        return "forbidden";
      case 404:
        return "not_found";
      case 409:
        return "conflict";
      case 422:
        return "validation_error";
      case 429:
        return "rate_limited";
      default:
        return status >= 500 ? "server_error" : "unknown_error";
    }
  }

  private static extractMessage(body: Record<string, unknown> | null): string {
    if (!body) return "Unknown error";
    if (typeof body.message === "string") return body.message;
    if (typeof body.error === "string") return body.error;
    return "Unknown error";
  }
}
