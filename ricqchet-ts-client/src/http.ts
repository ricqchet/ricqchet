import { RicqchetError } from "./error";

export type Auth = { type: "bearer"; token: string } | { type: "none" };

export interface RequestOptions {
  headers?: Record<string, string>;
  body?: string | null;
  auth?: Auth;
}

/**
 * Shared HTTP client for the Ricqchet SDK.
 * @internal
 */
export class HttpClient {
  readonly baseUrl: string;
  readonly timeout: number;

  constructor(baseUrl: string, timeout: number) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.timeout = timeout;
  }

  async request(
    method: string,
    path: string,
    options: RequestOptions = {}
  ): Promise<Response> {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.timeout);

    const headers = new Headers({
      "User-Agent": "ricqchet-typescript/0.1.0",
    });

    if (options.headers) {
      for (const [name, value] of Object.entries(options.headers)) {
        headers.set(name, value);
      }
    }

    if (options.auth?.type === "bearer") {
      headers.set("Authorization", `Bearer ${options.auth.token}`);
    }

    const body = options.body ?? null;

    if (body !== null && !headers.has("Content-Type")) {
      headers.set("Content-Type", "application/json");
    }

    try {
      return await fetch(`${this.baseUrl}${path}`, {
        method,
        headers,
        body,
        signal: controller.signal,
      });
    } catch (error: unknown) {
      throw RicqchetError.connectionError(error);
    } finally {
      clearTimeout(timeoutId);
    }
  }

  async parseError(response: Response): Promise<RicqchetError> {
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
}
