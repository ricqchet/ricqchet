---
name: tdd-writer
description: >
  Use this skill whenever the user wants to write a Technical Design Document (TDD) for a new feature.
  Triggers include: "write a TDD", "create a technical design doc", "let's design this feature", "I have a seed doc",
  "help me write up the design for", or any mention of a TDD/technical spec paired with a seed document, bullet points,
  or feature description. Also trigger if the user shares a rough feature outline and asks Claude to help think it through
  before implementation. Do NOT use for post-hoc documentation or simple README-style docs.
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# TDD Writer Skill

You are helping a user write a Technical Design Document (TDD). The process has four distinct phases — follow them in order and do not skip ahead.

---

## Phase 1: Ingest the Seed Document

The user will provide a seed document — typically a handful of bullet points describing the feature at a high level.

- **If no seed document was provided**, stop and ask the user to share one before continuing. Prompt them with something like: "To start the TDD seed round, please share a document (or paste in) your rough idea for the feature — even a few bullet points is enough." Do not proceed to research or questioning until you have a seed doc to work from.
- Read and acknowledge the seed document
- Immediately proceed to codebase/context research (Phase 2) **before asking any questions**
- Do NOT ask clarifying questions yet

---

## Phase 2: Research

Before questioning the user, gather as much context as possible yourself. This reduces burden on the user and makes your questions sharper.

**What to look for:**

- Relevant existing files, modules, or services that this feature will touch or extend
- Existing patterns: prior art, naming conventions, architectural patterns, data flow, error handling, testing approach
- Related past features or similar implementations that can serve as reference
- Config files, schema definitions, or API contracts relevant to the feature
- Any existing documentation (PRDs, READMEs, inline comments, other TDDs if present)

**How to research:**

- Use available tools to browse the codebase (file explorer, search, grep, etc.)
- Read relevant source files — don't just skim filenames
- Look at how similar features were structured end-to-end
- Note gaps: things the seed doc implies but that don't yet exist in the codebase

After research, append an `## Agent Research Notes` section to the seed document — placed directly after the user's initial notes and before any Q&A sections. Capture what you found there: relevant files/modules, existing patterns to follow, similar prior implementations, schema or contract touchpoints, and any gaps you noticed. This keeps your research auditable alongside the seed doc rather than buried in chat.

Then, in chat, briefly summarize what you found (2–4 sentences) so the user knows you've done your homework, point them to the new `## Agent Research Notes` section, and proceed to Phase 3.

---

## Phase 3: Multi-Round Questioning

Your goal is to reach **at least 95% confidence** in your understanding of both the business requirements and the technical implementation before writing anything.

### Q&A Lives in the Seed Document

Questions and answers are tracked in the seed document itself — not in chat. This keeps the Q&A auditable and separate from conversation noise.

**Your workflow each round:**

1. Write your questions directly into the seed document under a `## Questions — Round N` section, formatted as a numbered list
2. Tell the user in chat that you've added Round N questions to the seed doc and ask them to answer there, then ping you when done
3. When the user returns, re-read the seed document to get their answers
4. Assess your confidence level and either proceed to writing or append a new `## Questions — Round N+1` section

**Formatting questions in the doc:**

Each question is a numbered item followed by a `> Answer:` blockquote placeholder on the next line for the user to fill in.

```markdown
## Questions — Round 1

1. Question text here?

> Answer:

2. Question text here?

> Answer:

...
```

Leave the `> Answer:` line blank — the user fills it in directly under each question.

### Ground Rules

- Ask questions in **multiple rounds** — do not front-load everything into one giant list
- Each round should have **3–6 focused questions**, grouped thematically
- After each round, process the user's answers and assess: do you have enough to write a high-quality TDD?
- If yes, proceed to Phase 4. If not, add another round to the doc.
- Be explicit about your confidence level when telling the user you've added questions (e.g., "I'm at about 70% — I've added Round 2 to the doc.")
- Do not proceed to writing until you're at 95%+ confidence

### Question Categories

Use these as a guide — not all will apply to every feature:

**Business / Product**
- What problem does this solve? Who benefits?
- What does success look like? Are there measurable outcomes?
- Are there non-goals or explicit out-of-scope items?

**Technical Scope**
- Which services, APIs, or data stores are involved?
- Are there new dependencies, or can this be built on existing infrastructure?
- What are the expected data shapes / payload structures?
- Are there schema changes required?

**Integration & Interfaces**
- What does this expose (API endpoints, UI, events, etc.)?
- Who are the consumers of this feature (internal services, third parties, end users)?
- Are there contracts or backward compatibility concerns?

**Edge Cases & Error Handling**
- What happens when inputs are invalid or upstream services fail?
- Are there race conditions or concurrency concerns?
- What are the failure modes and how should they be handled?

**Operational & Security**
- Are there auth requirements (JWT session for the dashboard, API-key/Bearer for the API)?
- Is the feature correctly scoped per tenant (multi-tenant isolation)?
- Logging (structured `Logger` metadata) and telemetry/metrics needs?
- Are there rate-limiting or quota concerns?

**Delivery & Reliability**
- Does this touch message delivery, retries, or backoff behavior?
- Is the work idempotent — safe under retries and at-least-once delivery?
- Does it need a new Oban worker or queue, or change an existing one?
- What happens on permanent failure — does it route to the DLQ, and is the consumer notified?
- Are there fan-out, batching, or scheduling implications?

**Testing**
- What kinds of tests are expected (ExUnit unit/context tests, `ConnCase` API tests, `Phoenix.LiveViewTest`, `ChannelCase`)?
- Are there existing test patterns to follow (e.g. `create_tenant_with_api_key/3` in `DataCase`, `Mox` for mocking, `Bypass` for HTTP stubbing)?
- Are there tricky scenarios that will need specific test coverage?

---

## Phase 4: Write the TDD

Once you've reached 95%+ confidence, write the TDD.

### Where it goes and how it's structured

Write the TDD to `docs/tdd-<feature-slug>.md` (matching the existing convention — see `docs/tdd-channels.md`). There is no template file; match the structure and formality of the existing TDDs in `docs/`.

### Writing Guidelines

- Write in clear, precise technical prose — this is an engineering document.
- Balance specificity with clarity. Don't be overly-verbose. Keep readability in mind so that readers can get a deep understanding of the problem and proposed solution without spending too much time reading fluff.
- Be specific: prefer "the `messages` table gains a `delivered_at` timestamp column" over "we'll update the schema".
- Call out decisions explicitly, especially non-obvious ones.
- Flag genuine open questions as such — don't paper over unknowns.
- Omit sections that genuinely don't apply; don't pad with boilerplate.
- Match the formality and conventions of any existing TDDs in the codebase.

---

## Checklist Before Handing Off

Before presenting the TDD to the user, verify:

- [ ] All answers from the Q&A rounds are reflected in the doc
- [ ] Non-goals are clearly stated
- [ ] Data model changes (if any) are fully specified, including Ecto migrations
- [ ] Error handling is addressed
- [ ] Delivery/reliability impact is addressed (retries, idempotency, DLQ, Oban queues — or explicitly stated as "no delivery impact")
- [ ] Open questions are surfaced, not hidden
- [ ] The doc reads coherently end-to-end