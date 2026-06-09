Open a pull request for the current branch against `main`.

> **Monorepo:** the Elixir server lives in `ricqchet-web/`, the TypeScript client in `ricqchet-ts-client/`. Run every `mix` command and resolve relative source paths (`docs/`, `priv/repo/migrations/`, …) from inside `ricqchet-web/`. For TypeScript-client changes, run the `npm` checks (`build`, `test`, `lint`, `format:check`) from `ricqchet-ts-client/` instead of `mix precommit`.

## Arguments

- `$ARGUMENTS` — Pass `draft` to create a draft PR (e.g., `/pull-request draft`). If omitted, creates a regular PR.

## Steps

1. **Pre-flight checks** — Before opening the PR, ensure the code is ready:
   - Run `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, credo --strict, dialyzer, test)
   - If any step fails, fix the issue before proceeding

2. **Rebase on origin/main** — Ensure the branch is up to date:
   - Run `git fetch origin main`
   - Run `git rebase origin/main`
   - If there are conflicts, resolve them one file at a time:
     - Read the conflicting file to understand both sides
     - Apply the correct resolution preserving intent from both branches
     - Run `git add <file>` and `git rebase --continue`
   - After rebase, re-run pre-flight checks (`mix precommit`) to ensure nothing broke

3. **Analyze changes** — Review all commits on this branch vs `origin/main`:
   - Run `git log origin/main..HEAD --oneline` to see all commits
   - Run `git diff origin/main...HEAD` to see the full diff
   - Identify if any Ecto migration files are included (`priv/repo/migrations/`)

4. **Draft the PR** — Prepare the PR title, labels, and body:
   - **Title**: Use a concise, descriptive title (under 70 characters)
   - **Labels**: Add the `migration` label if the branch includes any Ecto migration files
   - **Body** should include these sections:

     ### Summary
     A succinct description of what changed and why. Include a mermaid diagram if the changes involve schema changes, new flows, or architectural changes.

     ### Complexity Notes
     Flag any areas of complexity, risk, or non-obvious behavior that reviewers should pay close attention to. If there are none, omit this section.

     ### Test Steps
     Provide concrete, numbered steps a reviewer can follow to verify the changes work correctly. Be specific — include URLs, commands, or UI flows to check.

     ### Checklist
     - [ ] Tests added/updated
     - [ ] Documentation in `docs/` updated (if the change affects a documented feature — see CLAUDE.md)
     - [ ] Index migrations use `create index(..., concurrently: true)` with `@disable_ddl_transaction true` (if adding indexes to large tables)
     - [ ] OpenAPI schema updated (OpenApiSpex, `/api/docs`) if API endpoints or request/response shapes changed

5. **Push and create** — Push the branch and create the PR:
   - `git push -u origin HEAD`
   - If `$ARGUMENTS` is `draft`, run `gh pr create --draft` with the drafted title and body
   - Otherwise, run `gh pr create` with the drafted title and body

6. **Return the PR URL** to the user when done.
