# AGENTS.md

Ricqchet is a self-hosted **HTTP message relay** (guaranteed delivery, retries, fan-out, batching, scheduling, signed webhooks, dead-letter queue) combined with **real-time WebSocket channels** (public, private and presence channels with history, recovery and lifecycle webhooks). Think Upstash QStash and Pusher in one service that a team runs on its own infrastructure.

This is a **monorepo** with two independently released projects:

| Path                  | Project                                                   | Stack                       | Detailed guide                 |
| --------------------- | --------------------------------------------------------- | --------------------------- | ------------------------------ |
| `ricqchet-web/`       | Ricqchet server: HTTP message relay + real-time channels  | Elixir / Phoenix 1.8 + Oban | `ricqchet-web/AGENTS.md`       |
| `ricqchet-ts-client/` | `@ricqchet/client`: TypeScript/JavaScript client          | TypeScript / tsup / vitest  | `ricqchet-ts-client/AGENTS.md` |

**Run project commands from inside the relevant subdirectory.** `mix` tasks live in `ricqchet-web/`, and `npm` scripts live in `ricqchet-ts-client/`. The repo root holds only shared tooling: `.github/`, `mise.toml`, `release-please-config.json`, `.release-please-manifest.json`, `.commitlintrc.yml`, `.claude/`, `.agents/`, `CLAUDE.md` and this file. Tool versions (Erlang 27, Elixir 1.18, Node 20) are pinned in `mise.toml`, so run `mise install` at the root.

**Read the subproject's `AGENTS.md` before changing it.** Each one covers architecture, conventions, testing and the pre-commit gate for its stack.

## Server: `ricqchet-web/`

Quick reference:

```bash
cd ricqchet-web
mix setup       # deps, DB, migrations, seed (needs PostgreSQL 15+)
mix phx.server  # http://localhost:4000, API docs at /api/docs
mix precommit   # REQUIRED before committing server changes
```

`mix precommit` runs, in order: `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `credo --strict`, `dialyzer`, `test`. User-facing server docs live in `ricqchet-web/docs/`.

## TypeScript client: `ricqchet-ts-client/`

```bash
cd ricqchet-ts-client
npm ci
npm run build && npm test && npm run lint && npm run format:check && npm run typecheck
```

## Cross-Project Changes

The client mirrors the server's REST routes, JSON shapes, `Ricqchet-*` publish headers, WebSocket protocol and signature format. When a server change touches one of those contracts:

1. Update the server, its tests, its OpenAPI schemas and `ricqchet-web/docs/`.
2. Update `ricqchet-ts-client/` (types, methods, tests, README) in the same PR where practical. Otherwise open a follow-up issue labeled `ts-client`.
3. Keep server-side changes backward compatible for published client versions, or mark them as breaking (`!` / `BREAKING CHANGE:`).

## Working Rules

- Keep changes scoped to the task. Do not reformat or refactor unrelated code.
- Never commit secrets. `.env*` files are denied to agents in `.claude/settings.json`; the signing secret, JWT secret and API keys come from the environment.
- Add or update tests with every behavior change, and run the subproject's full gate before committing. Do not commit if it fails.
- Update user-facing docs (`ricqchet-web/docs/`, the READMEs) in the same change as the behavior they describe.

## Commits & Releases

- **Conventional Commits**, lowercase subjects, 100-character header limit (commitlint runs at the repo root over both projects). Use a project scope when a change is specific to one side: `feat(web): …`, `fix(ts-client): …`. The Elixir side also uses subsystem scopes (`refactor(delivery): …`). Never add `Co-authored-by` trailers.
- **release-please manifest mode**: each project releases on its own cadence, `ricqchet-v*` (server, auto-deploys to Fly.io and publishes a Docker image to GHCR) and `ts-client-v*` (client, npm). CHANGELOGs and versions are generated inside each subproject. Do not edit them by hand.
- **CI** runs only the stack(s) a PR changes, and the `All checks passed` job is the single required gate.

## Agent Skills

Shared skills live in `.agents/skills/` (mirrored for Claude in `.claude/skills/`): `implement-issue`, `commit-changes`, `pull-request`, `incorporate-feedback`, `rebase-on-main`, `qa` and `tdd-writer`. They operate on the Elixir server, so run their `mix` tasks and resolve their source paths (`lib/`, `priv/`, `test/`, `docs/`) from inside `ricqchet-web/`. For client work, follow `ricqchet-ts-client/AGENTS.md` directly.
