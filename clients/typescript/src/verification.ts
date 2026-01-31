import { createHmac, timingSafeEqual } from "crypto";

const SIGNATURE_HEADER = "x-ricqchet-signature";
const MESSAGE_ID_HEADER = "x-ricqchet-message-id";
const BATCH_ID_HEADER = "x-ricqchet-batch-id";
const ATTEMPT_HEADER = "x-ricqchet-attempt";

/**
 * Metadata extracted from Ricqchet delivery headers.
 */
export interface VerificationMetadata {
  /** The message ID (for single message deliveries) */
  messageId: string | null;
  /** The batch ID (for batch deliveries) */
  batchId: string | null;
  /** The delivery attempt number (1-based) */
  attempt: number | null;
  /** The signature timestamp */
  timestamp: number;
}

/**
 * Result of signature verification.
 */
export type VerificationResult =
  | { valid: true; metadata: VerificationMetadata }
  | {
      valid: false;
      error:
        | "missing_signature"
        | "invalid_format"
        | "invalid_signature"
        | "signature_expired";
    };

/**
 * Options for signature verification.
 */
export interface VerifyOptions {
  /** Maximum age of signature in seconds (default: 300, set to null to disable) */
  maxAge?: number | null;
}

/**
 * Verifies a Ricqchet webhook signature.
 *
 * @param signatureHeader - The X-Ricqchet-Signature header value
 * @param payload - The raw request body
 * @param signingSecret - The signing secret (binary)
 * @param options - Verification options
 * @returns Verification result with validity and timestamp
 *
 * @example
 * ```typescript
 * const result = verifySignature(
 *   req.headers['x-ricqchet-signature'],
 *   rawBody,
 *   signingSecret
 * );
 *
 * if (!result.valid) {
 *   return res.status(401).send('Invalid signature');
 * }
 *
 * console.log('Verified at timestamp:', result.metadata.timestamp);
 * ```
 */
export function verifySignature(
  signatureHeader: string | undefined,
  payload: string | Buffer,
  signingSecret: Uint8Array | Buffer,
  options?: VerifyOptions
): VerificationResult {
  // Use 300 as default only if maxAge is undefined (not null)
  const maxAge = options?.maxAge === undefined ? 300 : options.maxAge;

  if (!signatureHeader) {
    return { valid: false, error: "missing_signature" };
  }

  const parsed = parseSignature(signatureHeader);
  if (!parsed) {
    return { valid: false, error: "invalid_format" };
  }

  const { timestamp, signature } = parsed;

  // Check timestamp
  if (maxAge !== null) {
    const now = Math.floor(Date.now() / 1000);
    if (now - timestamp > maxAge) {
      return { valid: false, error: "signature_expired" };
    }
  }

  // Verify HMAC
  const payloadString =
    typeof payload === "string" ? payload : payload.toString("utf-8");
  const signedPayload = `${timestamp}.${payloadString}`;

  const expectedSignature = createHmac("sha256", signingSecret)
    .update(signedPayload)
    .digest("hex");

  const providedBuffer = Buffer.from(signature.toLowerCase(), "hex");
  const expectedBuffer = Buffer.from(expectedSignature, "hex");

  if (providedBuffer.length !== expectedBuffer.length) {
    return { valid: false, error: "invalid_signature" };
  }

  if (!timingSafeEqual(providedBuffer, expectedBuffer)) {
    return { valid: false, error: "invalid_signature" };
  }

  return {
    valid: true,
    metadata: {
      messageId: null,
      batchId: null,
      attempt: null,
      timestamp,
    },
  };
}

/**
 * Verifies a request from an Express-like request object.
 *
 * @param headers - Request headers (case-insensitive)
 * @param body - Raw request body
 * @param signingSecret - The signing secret
 * @param options - Verification options
 * @returns Verification result with metadata
 *
 * @example
 * ```typescript
 * // Express middleware
 * app.use('/webhook', express.raw({ type: 'application/json' }), (req, res) => {
 *   const result = verifyRequest(req.headers, req.body, signingSecret);
 *
 *   if (!result.valid) {
 *     return res.status(401).json({ error: result.error });
 *   }
 *
 *   // Process webhook
 *   console.log('Message ID:', result.metadata.messageId);
 * });
 * ```
 */
export function verifyRequest(
  headers: Record<string, string | string[] | undefined>,
  body: string | Buffer,
  signingSecret: Uint8Array | Buffer,
  options?: VerifyOptions
): VerificationResult {
  const signatureHeader = getHeader(headers, SIGNATURE_HEADER);

  const result = verifySignature(signatureHeader, body, signingSecret, options);

  if (!result.valid) {
    return result;
  }

  // Extract metadata from headers
  return {
    valid: true,
    metadata: {
      messageId: getHeader(headers, MESSAGE_ID_HEADER) ?? null,
      batchId: getHeader(headers, BATCH_ID_HEADER) ?? null,
      attempt: parseAttempt(getHeader(headers, ATTEMPT_HEADER)),
      timestamp: result.metadata.timestamp,
    },
  };
}

function parseSignature(
  header: string
): { timestamp: number; signature: string } | null {
  const match = header.match(/^t=(\d+),v1=([a-f0-9]+)$/i);
  if (!match) {
    return null;
  }

  return {
    timestamp: parseInt(match[1], 10),
    signature: match[2],
  };
}

function getHeader(
  headers: Record<string, string | string[] | undefined>,
  name: string
): string | undefined {
  // Case-insensitive header lookup
  const lowerName = name.toLowerCase();

  for (const [key, value] of Object.entries(headers)) {
    if (key.toLowerCase() === lowerName && value !== undefined) {
      return Array.isArray(value) ? value[0] : value;
    }
  }

  return undefined;
}

function parseAttempt(value: string | undefined): number | null {
  if (!value) return null;
  const parsed = parseInt(value, 10);
  return isNaN(parsed) ? null : parsed;
}
