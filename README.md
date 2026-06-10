# Ricqchet

**Self-hosted HTTP message relay and real-time channels.** Publish messages once — Ricqchet handles guaranteed delivery, retries, fan-out, batching, and scheduling. Connect clients with WebSocket channels that include history, presence, and cache.

> Own your infrastructure. No per-message pricing, no vendor lock-in, no data leaving your stack.

This is the Ricqchet **monorepo** — the server and its official TypeScript client live and ship from here.

---

## Repository layout

| Path | What it is | Stack | Releases as |
|------|-----------|-------|-------------|
| [`ricqchet-web/`](ricqchet-web/) | The Ricqchet server — JSON relay API, LiveView dashboard, real-time channels | Elixir / Phoenix 1.8 + Oban | `ricqchet-v*` → Fly.io |
| [`ricqchet-ts-client/`](ricqchet-ts-client/) | Official TypeScript/JavaScript client `@ricqchet/client` — relay, channels, React/Next helpers | TypeScript | `ts-client-v*` → npm |

Each subproject owns its own README, CHANGELOG, dependencies, and build tooling:

- **Server:** [`ricqchet-web/README.md`](ricqchet-web/README.md) — setup, API, deployment, configuration, full docs in [`ricqchet-web/docs/`](ricqchet-web/docs/)
- **TypeScript client:** [`ricqchet-ts-client/README.md`](ricqchet-ts-client/README.md) — install, usage, realtime/React

---

## What Ricqchet does

**Message relay** — your application POSTs an event to Ricqchet, which queues it, retries with exponential backoff, signs each delivery with an HMAC signature, and routes exhausted messages to a dead-letter queue. Think Upstash QStash, self-hosted and open-source.

**Real-time channels** — broadcast events to WebSocket clients instantly. Public, private (auth-gated), and presence channels with event history, cache channels, client-to-client messaging, and per-namespace config. Think Pusher or Ably, on your own infrastructure.

See the [server README](ricqchet-web/README.md) for the full feature matrix and API examples.

---

## Working in this repo

### Prerequisites

Tool versions are pinned in the root [`mise.toml`](mise.toml) (Erlang, Elixir, Node). Using [mise](https://mise.jdx.dev/)? Run `mise install` from the repo root to get all three.

### Server — `ricqchet-web/`

```bash
cd ricqchet-web
mix setup        # install deps, create DB, run migrations, seed
mix phx.server   # http://localhost:4000  (API docs at /api/docs)
mix precommit    # REQUIRED gate before committing server changes
```

### TypeScript client — `ricqchet-ts-client/`

```bash
cd ricqchet-ts-client
npm ci
npm run build
npm test
npm run lint && npm run format:check
```

---

## CI & releases

- **CI** ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) detects which subproject a pull request touches and runs only that stack. A single `All checks passed` gate aggregates every job and is the only status check you need to mark *required* in branch protection — it stays green for changes that don't touch a given stack, which keeps the merge queue unblocked.
- **Releases** are managed by [release-please](https://github.com/googleapis/release-please) in manifest mode. Each project versions **independently**, with its own tag and CHANGELOG (`ricqchet-v*` for the server, `ts-client-v*` for the client). Merging a server release auto-deploys to Fly.io ([`deploy.yml`](.github/workflows/deploy.yml)) — for that hand-off to fire automatically, release-please must publish releases with a PAT secret (`RELEASE_PLEASE_TOKEN`), since GitHub suppresses workflow triggers from `GITHUB_TOKEN`-published releases; `deploy.yml` also supports manual `workflow_dispatch`.
- **Commits** follow [Conventional Commits](https://www.conventionalcommits.org/) (enforced by commitlint, lowercase subjects). Add a scope to signal the project when it helps: `feat(web): …`, `fix(ts-client): …`.

---

## Client libraries

- **TypeScript** — [`ricqchet-ts-client/`](ricqchet-ts-client/) (in this repo)
- **Elixir** — [ricqchet/elixir-client](https://github.com/ricqchet/elixir-client)

---

## License

MIT
