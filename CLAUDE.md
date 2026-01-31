# CLAUDE.md

Ricqchet is an HTTP message relay service with guaranteed delivery, retries, fan-out, batching, and scheduling. Built with Phoenix 1.8 (API-only) and Oban for job processing.

## Quick Reference

```bash
mix setup              # Install deps, create DB, run migrations
mix phx.server         # Start dev server (API docs at /api/docs)
mix test               # Run tests
mix precommit          # Pre-commit checks (see below)
```

## Before Committing

Use the precommit alias to run all quality checks:

```bash
mix precommit
```

This runs:
- `compile --warnings-as-errors` - No compiler warnings
- `format` - Auto-format code
- `credo --strict` - Static analysis
- `dialyzer` - Type checking
- `test` - All tests pass

## Commit Conventions

This project uses [conventional commits](https://www.conventionalcommits.org/) enforced by commitlint.

**Format:** `type: description`

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`

**Rules:**
- Messages must be **lowercase**
- Max 100 characters in header
- Never include "Co-authored By"

**Examples:**
```
feat: add message deduplication support
fix: correct retry backoff calculation
docs: update api reference for fan-out
refactor(delivery): extract retry logic to module
```

## Documentation Requirements

The `docs/` folder contains user-facing documentation. **Update docs when making changes that affect:**

- API endpoints or request/response formats → `docs/api-reference.md`
- Authentication or API keys → `docs/authentication.md`
- Batching behavior → `docs/batching.md`
- Configuration options → `docs/configuration.md`
- Delivery, retries, or timeouts → `docs/delivery.md`
- Core concepts or architecture → `docs/overview.md`
- Webhook consumer guidance → `docs/receiving-webhooks.md`

Keep the main `README.md` in sync for major feature additions.

## Project Structure

```
lib/
├── ricqchet/          # Core business logic (contexts)
├── ricqchet.ex        # Public API facade
├── ricqchet_web/      # Phoenix controllers, routes
└── ricqchet_web.ex    # Web module helpers
```

## Key Dependencies

- **Req** - HTTP client (never use httpoison, tesla, or httpc)
- **Oban** - Background job processing
- **OpenApiSpex** - API documentation at `/api/docs`

## Testing

```bash
mix test                    # Run all tests
mix test path/to/test.exs   # Run specific file
mix test --failed           # Re-run failed tests
```

Uses `Mox` for mocking and `Bypass` for HTTP stubbing.
