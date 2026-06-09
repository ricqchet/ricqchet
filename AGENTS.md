# AGENTS.md

This is the **Ricqchet monorepo**. See [`CLAUDE.md`](CLAUDE.md) for the full layout and how to work in each subproject.

- **`ricqchet-web/`** — Elixir / Phoenix server. Project-specific agent guidelines live in [`ricqchet-web/AGENTS.md`](ricqchet-web/AGENTS.md). Run `mix` from this directory.
- **`ricqchet-ts-client/`** — TypeScript client (`@ricqchet/client`). Run `npm` from this directory.

Run project commands from inside the relevant subdirectory, not the repo root. The root holds only shared tooling (`.github/`, `mise.toml`, release-please config, commitlint, `.claude/`).
