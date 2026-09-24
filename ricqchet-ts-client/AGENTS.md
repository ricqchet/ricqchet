# AGENTS.md

`@ricqchet/client` is the official TypeScript/JavaScript client for Ricqchet. It covers the **relay API** (publish, fan-out, batching, message status and cancellation), server-side **channel events** (trigger, batch trigger, list, history, members, force-disconnect), **webhook signature verification**, and browser **real-time subscriptions** with React and Next.js helpers.

> **Monorepo:** this is the client subproject (`ricqchet-ts-client/`) of the [Ricqchet monorepo](../AGENTS.md). Run all `npm` commands and resolve every relative path in this file from inside `ricqchet-ts-client/`. The server it talks to lives in `../ricqchet-web/`.

## Quick Reference

```bash
npm ci                  # Install exact dependencies from package-lock.json
npm run build           # tsup → dist/ (CJS + ESM + .d.ts for every entry point)
npm test                # vitest run
npm run test:watch      # vitest in watch mode
npm run typecheck       # tsc --noEmit
npm run lint            # eslint src test
npm run format          # prettier --write
npm run format:check    # prettier --check
```

Node 20 is pinned in the root `mise.toml`; the package supports Node `>=18`.

## Before Committing

CI runs these in order. Run all of them and fix every failure before committing:

```bash
npm run build && npm test && npm run lint && npm run format:check && npm run typecheck
```

`typecheck` is not in CI, but `tsup` does not fail on every type error, so run it anyway.

## Package Layout

The package ships four entry points. Each is a separate `tsup` entry and a separate `exports` subpath in `package.json`:

| Import path | Source | Purpose | Runtime deps |
| --- | --- | --- | --- |
| `@ricqchet/client` | `src/index.ts` | `RicqchetClient`, `verifyRequest` / `verifySignature`, `RicqchetError`, channel-name helpers, shared types | none |
| `@ricqchet/client/realtime` | `src/realtime/index.ts` | `RicqchetRealtime`: WebSocket subscriptions, presence, client events | `phoenix` (peer) |
| `@ricqchet/client/react` | `src/react/index.ts` | `RicqchetProvider` and `useRicqchet*` hooks (`"use client"` boundary) | `react` (peer) |
| `@ricqchet/client/next` | `src/next/index.ts` | `createChannelAuthRoute`, `verifyChannelWebhookRequest` for App Router route handlers | none |

```text
src/
├── index.ts          # Root entry: public exports only
├── client.ts         # RicqchetClient: relay + server-side channel REST calls
├── http.ts           # Internal fetch wrapper (timeout, auth header, User-Agent)
├── error.ts          # RicqchetError and HTTP status → error type mapping
├── verification.ts   # HMAC-SHA256 webhook signature verification
├── channels.ts       # Channel-name validation and type detection
├── types.ts          # Shared request/response types
├── realtime/         # Browser realtime client
│   ├── phoenix.ts    # The ONLY module that imports `phoenix`
│   ├── client.ts     # RicqchetRealtime
│   └── types.ts
├── react/index.ts    # Provider + hooks
└── next/index.ts     # Next.js route helpers
test/                 # vitest suites, one per area (client, channels, realtime, react, next, verification)
```

## Design Rules

- **Keep the core dependency-free.** `src/index.ts` and everything it imports must not import `phoenix`, `react`, or any runtime package. It relies only on `fetch`, `AbortController` and `Headers`, plus Node's built-in `crypto` in `verification.ts`.
- **Peer dependencies stay optional and external.** `phoenix` and `react` are optional peers listed in `tsup.config.ts` `external`. Never bundle them, and never import them from outside their subpath entry.
- **Isolate `phoenix` behind `src/realtime/phoenix.ts`.** The rest of the realtime code depends on the small `PhoenixSocket` / `PhoenixChannel` / `PhoenixPush` interfaces, so tests can inject a fake socket through `SocketFactory`.
- **Adding an entry point** means updating all three: `tsup.config.ts` `entry`, `package.json` `exports` (with `import`/`require` × `types`/`default`), and the README.
- **Errors are always `RicqchetError`.** Map HTTP failures with `RicqchetError.fromResponse` and network or timeout failures with `RicqchetError.connectionError`. Callers branch on `error.type`, so do not throw bare `Error` from public methods. Add a new `RicqchetErrorType` member only when callers need to branch on it.
- **Validate locally before sending** when the server has a hard limit the client knows about. Throw `validation_error` without making a request, as `publishFanOut` does for its 100-destination cap. Keep these limits in named constants that match the server (the server caps triggers at 10 channels and batch triggers at 10 events).
- **Channel names are bare.** Subscribe and trigger with the channel name only (`private-order-123`), never with an application prefix. The server resolves the application from the API key.
- **Never make a `relay` key look browser-safe.** Browser examples, React and realtime docs must use a `subscribe`-scoped key. The relay key and signing secret are server-only.
- **Public API is what `src/index.ts` and the subpath `index.ts` files export.** Anything else is internal (mark it `@internal`). Removing or renaming an export, or changing a signature, is a breaking change: use `feat(ts-client)!:` / `BREAKING CHANGE:` in the commit.
- Keep the `User-Agent` string in `src/http.ts` in sync with the package version when releasing.

## Keeping in Sync with the Server

The client mirrors the server's REST and WebSocket contracts, which are defined in `../ricqchet-web/`:

- REST routes: `../ricqchet-web/lib/ricqchet_web/router.ex`. Request and response shapes: `lib/ricqchet_web/controllers/*_json.ex` and `lib/ricqchet_web/schemas/`.
- Publish headers (`Ricqchet-Destination`, `Ricqchet-Delay`, `Ricqchet-Dedup-Key`, `Ricqchet-Batch-*`, `Ricqchet-Forward-*`, …): `../ricqchet-web/docs/api-reference.md`.
- WebSocket protocol, private-channel auth and client events: `../ricqchet-web/docs/channels.md` and `lib/ricqchet_web/channels/`.
- Signature format `t=<unix>,v1=<hex hmac-sha256 of "<t>.<raw body>">`: `lib/ricqchet/delivery/signer.ex`.

The server returns snake_case JSON (`message_id`), and the client exposes camelCase (`messageId`). Convert at the boundary in `client.ts`, and keep the types in `types.ts` camelCase.

When a server change affects any of these contracts, update the client, its tests and the README in the same PR where practical.

## Testing

- **vitest** with `globals: true` and the `node` environment by default. Suites that need a DOM start with `// @vitest-environment happy-dom` (see `test/react.test.ts`).
- **HTTP:** mock with `msw` (`setupServer` from `msw/node`), and use `onUnhandledRequest: "error"` so unexpected calls fail the test. Assert on the outgoing method, path, headers (especially `Authorization` and `Ricqchet-*`) and body, not just the parsed result.
- **Realtime / React:** inject fake `PhoenixSocket` / `PhoenixChannel` / `PhoenixPush` implementations through the socket factory rather than opening real WebSockets. Use `@testing-library/react`'s `renderHook` and `act` for hooks.
- Every public method needs a success test and at least one error-mapping test (4xx → typed `RicqchetError`, network failure → `connection_error`).
- Verification tests must cover a valid signature, a tampered payload, a wrong secret, a malformed or missing header and an expired timestamp (see `test/verification.test.ts`).
- Do not hit a real Ricqchet server in unit tests.

## Style

- TypeScript `strict` mode. Avoid `any`, because lint warns on it. Prefer `unknown` and narrow it.
- Prettier: double quotes, semicolons, `trailingComma: "es5"`, 80 columns. Run `npm run format`; do not hand-format.
- Unused parameters are prefixed with `_`.
- Document every public class, method and option with TSDoc. The README examples are the user-facing reference, so keep them compiling and accurate.

## Releases

- Released independently by release-please as `ts-client-v*` (npm package `@ricqchet/client`). Do not edit `package.json` `version` or a CHANGELOG by hand.
- Use Conventional Commits with the `ts-client` scope: `feat(ts-client): add getMessage retries option`, `fix(ts-client): map 429 to rate_limited`. `feat` bumps minor (pre-1.0) and `fix` bumps patch.
- `prepublishOnly` runs the build, and only `dist/` is published (`files` in `package.json`).
