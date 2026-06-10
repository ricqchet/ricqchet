---
name: commit-changes
description: Review all uncommitted changes and create a well-structured conventional commit.
argument-hint: "[optional context]"
disable-model-invocation: true
---

Review all uncommitted changes and create a well-structured commit using conventional commit format.

> **Monorepo:** two projects share this repo — the Elixir server in `ricqchet-web/` and the TypeScript client in `ricqchet-ts-client/`. Run the pre-flight gate inside whichever you changed: `mix precommit` from `ricqchet-web/`, or `npm run build && npm test && npm run lint && npm run format:check` from `ricqchet-ts-client/`. Resolve relative paths from that subdirectory, and prefer a project scope for single-side commits — `feat(web): …`, `fix(ts-client): …`.

## Steps

1. **Pre-flight checks** — Ensure the code is ready to commit:
   - Run `mix precommit` — the project gate that runs, in order: `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `credo --strict`, `dialyzer`, and `test`
   - If any step fails, fix the issue before proceeding — do not commit a failing tree

2. **Review changes** — Understand what's being committed:
   - Run `git status` to see all modified/untracked files
   - Run `git diff` to review unstaged changes
   - Run `git diff --cached` to review already-staged changes
   - Run `git log --oneline -5` to see recent commit style for context

3. **Stage files** — Add relevant files to staging:
   - Stage files by name (avoid `git add -A` or `git add .`)
   - Do NOT stage files that contain secrets (`.env`, credentials, etc.)
   - If there are unrelated changes, group them into separate logical commits

4. **Draft commit message** — Use conventional commit format (enforced by commitlint):
   - Format: `<type>(<scope>): <description>`
   - Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `style`, `perf`, `ci`, `build`, `revert`
   - Scope: the domain or area affected (e.g., `delivery`, `messages`, `batches`, `dlq`, `auth`, `api`)
   - Description: concise summary of the "why", not the "what"
   - **Rules**: message must be **lowercase**, header max **100 characters**, and **never** include a `Co-authored-by` trailer
   - Add a body paragraph if the change is non-trivial, explaining motivation or trade-offs
   - Reference GitHub issues when applicable (e.g., `Closes #123`)

5. **Create the commit** — Use a HEREDOC for the message to preserve formatting:
   ```
   git commit -m "$(cat <<'EOF'
   type(scope): description

   Optional body with more context.
   EOF
   )"
   ```

6. **Verify** — Run `git status` after committing to confirm success.

## Examples

```
feat(delivery): add jitter to retry backoff

Closes #456
```

```
fix(batches): prevent duplicate fan-out on retry

The batch worker wasn't deduplicating by message id,
causing downstream consumers to receive duplicate deliveries.
```

```
refactor(dlq): extract notification payload builder
```
