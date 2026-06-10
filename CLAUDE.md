# CLAUDE.md

Ricqchet is a **monorepo** with two independently released projects:

| Path | Project | Stack | Detailed guide |
|------|---------|-------|----------------|
| `ricqchet-web/` | Ricqchet server — HTTP message relay + real-time channels | Elixir / Phoenix 1.8 + Oban | [`ricqchet-web/CLAUDE.md`](ricqchet-web/CLAUDE.md) |
| `ricqchet-ts-client/` | `@ricqchet/client` — TypeScript/JavaScript client | TypeScript / tsup / vitest | [`ricqchet-ts-client/README.md`](ricqchet-ts-client/README.md) |

**Run project commands from inside the relevant subdirectory.** `mix` tasks live in `ricqchet-web/`; `npm` scripts live in `ricqchet-ts-client/`. The repo root holds only shared tooling: `.github/`, `mise.toml`, `release-please-config.json`, `.release-please-manifest.json`, `.commitlintrc.yml`, `.claude/`, and this file.

## Server — `ricqchet-web/`

See [`ricqchet-web/CLAUDE.md`](ricqchet-web/CLAUDE.md) for the full guide (architecture, contexts, Oban queues, structured logging, telemetry, and documentation requirements). Quick reference:

```bash
cd ricqchet-web
mix setup       # deps, DB, migrations, seed
mix precommit   # REQUIRED before committing server changes
```

`mix precommit` runs, in order: `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `credo --strict`, `dialyzer`, `test`. Server docs live in `ricqchet-web/docs/`.

## TypeScript client — `ricqchet-ts-client/`

```bash
cd ricqchet-ts-client
npm ci
npm run build && npm test && npm run lint && npm run format:check
```

## Commits & releases

- **Conventional Commits**, lowercase subjects, ≤100-char header (commitlint runs at the repo root over both projects). Use an optional project scope when a change is specific to one side: `feat(web): …`, `fix(ts-client): …`. The Elixir side also uses subsystem scopes (`refactor(delivery): …`).
- **release-please manifest mode**: each project releases on its own cadence — `ricqchet-v*` (server, auto-deploys to Fly.io) and `ts-client-v*` (client). CHANGELOGs are generated inside each subproject, not at the root.
- **CI** runs only the stack(s) a PR changes; the `All checks passed` job is the single required gate.

## Tooling note

The shared commands and skills under `.claude/` operate on the Elixir server: run their `mix` tasks and resolve their source paths (`lib/`, `priv/`, `test/`, `docs/`) from inside `ricqchet-web/`.
