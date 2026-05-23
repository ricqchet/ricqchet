Implement the changes described in one or more GitHub issues passed via $ARGUMENTS.

## Arguments

`$ARGUMENTS` accepts one or more GitHub issue numbers, optionally followed by free-form additional context:

- `123` — single issue
- `#123 #456` — multiple with hash prefixes
- `123,456,789` — comma-separated
- `#123, #456` — comma-separated with hashes
- `123,456 prefer a single migration and skip the UI changes for now` — issue numbers followed by additional context

**Parsing rule:**

1. Tokenize `$ARGUMENTS` on whitespace, preserving the original text.
2. Walk tokens left-to-right. A token is an **issue token** if, after stripping any leading `#` and trailing `,`, it is purely digits. Collect issue numbers from these tokens.
3. Stop at the first token that is **not** an issue token. That token and everything after it (rejoined with their original whitespace) is the **additional context**.
4. If every token is an issue token, there is no additional context.

Examples:

- `123,456,789` → issues: `[123, 456, 789]`, context: _(none)_
- `#123 #456 please keep the changes minimal` → issues: `[123, 456]`, context: `please keep the changes minimal`
- `789 use the v2 migration pattern and add a feature flag` → issues: `[789]`, context: `use the v2 migration pattern and add a feature flag`

## Steps

1. **Fetch the issues** — Get the full details for each issue:
   - Parse `$ARGUMENTS` using the rule above to extract all issue numbers **and any trailing additional context**
   - For each issue number, run `gh issue view <number> --json title,body,labels,comments`
   - Read all titles, descriptions, and comments carefully for every issue
   - If additional context was provided, treat it as user-supplied guidance that augments (and may override) the issue text — surface it explicitly back to the user so they can confirm you parsed it correctly

2. **Understand the context** — Research the codebase before making changes:
   - Identify which domains, files, and systems are affected across all issues
   - Read the relevant source files to understand the current behavior
   - Check `docs/` for any existing documentation on the affected areas
   - Review related tests to understand expected behavior and edge cases
   - If any issue references other issues or PRs, fetch those for additional context
   - When working with multiple issues, identify shared concerns, overlapping files, and dependencies between the issues

3. **Ask clarifying questions** — Before implementing, check for ambiguity:
   - If any issue is underspecified, missing acceptance criteria, or has multiple valid interpretations, stop and ask the user for clarification
   - If the combined scope seems larger than expected, confirm the approach before proceeding
   - If there are architectural decisions to make, present the options with trade-offs
   - When working with multiple issues, flag any conflicts or contradictions between issue requirements
   - If the additional context conflicts with anything in the issue bodies (e.g., the issue says "add a UI toggle" but the context says "skip the UI"), call this out explicitly and ask the user which should win before continuing

4. **Plan the implementation** — Outline the approach:
   - Enter plan mode and draft a step-by-step implementation plan
   - Plan a single unified implementation that addresses all issues cohesively
   - **Incorporate any additional context** from `$ARGUMENTS` into the plan — treat it as authoritative user guidance on scope, approach, or constraints
   - Identify all files that need to be created or modified
   - Note any migrations, new dependencies, or configuration changes required
   - Call out where issue requirements interact or depend on each other
   - Call out risks or areas that need extra care
   - Wait for the user to approve the plan before proceeding

5. **Implement the changes** — Execute the plan:
   - Follow the patterns and conventions documented in CLAUDE.md
   - Write tests alongside the implementation (not after)
   - Reference issue numbers in code comments only when the context isn't self-evident
   - Update documentation in `docs/` if the changes affect documented features
   - **Leverage agents and teams for parallel work** — when the implementation involves independent workstreams (e.g., a context + an API controller + a LiveView, or a context + an Oban worker, or multiple unrelated files), use subagents to work on them concurrently. Examples:
     - Spawn agents to research different parts of the codebase in parallel during the planning phase
     - Use agents to implement independent modules simultaneously (e.g., one for the context, one for tests)
     - Delegate verification (`mix precommit`) to a background agent while continuing work
   - Prefer agents over sequential execution whenever tasks don't depend on each other

6. **Verify** — Ensure everything works:
   - Run `mix precommit` (compile --warnings-as-errors, deps.unlock --unused, format, credo --strict, dialyzer, test)
   - This covers both existing and new tests; if any step fails, fix the issue before proceeding

7. **Report** — Summarize what was done:
   - List the files created or modified
   - Describe the approach taken and any trade-offs made
   - Note all issue numbers for commit messages (e.g., `Closes #123, Closes #456`)
   - Summarize which changes address which issues when working with multiple
   - Flag anything that needs manual testing or follow-up
