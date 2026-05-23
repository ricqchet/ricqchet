---
name: qa
description: >
  Run a QA test pass on uncommitted changes — or on a pre-existing Gherkin file passed as an argument.
  Use when the user says "run QA", "do a QA pass", "write QA scenarios", "test these changes end-to-end",
  "exercise this feature", or asks to verify a feature works before they ship it. With no argument,
  generates Gherkin scenarios from the diff. With a path argument, reads the Gherkin file and resumes
  mid-flow (skipping scenario authoring). Encodes the scenarios as native ExUnit tests
  (`Phoenix.LiveViewTest` for the dashboard, `ConnCase` for the JSON API, `ChannelCase` for channels),
  seeding data in-test via the SQL sandbox, and reports pass/fail per scenario. Do NOT use for routine
  unit/context test authoring (just write `mix test` files directly) or for design-phase work (use
  `tdd-writer`).
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# QA Skill

Use this skill to run an end-to-end QA test pass. The flow has up to five phases — execute them in order, but **skip phases that are already satisfied** based on the input you were given.

Ricqchet is an HTTP message-relay service: a JSON API (`/v1/...`), a Phoenix LiveView dashboard (`/dashboard`, `/applications`, `/team`), realtime channels, and Oban-backed delivery. QA here means **encoding scenarios as native ExUnit tests and running them under `mix test`** — not driving a real browser. Phoenix LiveView is server-rendered, so `Phoenix.LiveViewTest` exercises the full mount → event → render cycle in-process, against the transactional SQL sandbox.

## How the input shapes the flow

Inspect what the user passed in (or didn't):

- **No argument** → start at Phase 1 and run every phase.
- **A path to a `.feature` file** → skip Phase 1 (assume the feature file already represents the user's intent) and skip Phase 2 (don't rewrite scenarios). Read the file, then jump into Phase 3.
- **A path to something else** (e.g. a TDD or seed notes) → treat it as additional context for Phase 1 and proceed normally.

When given a `.feature` file, your first action is to **read it in full** and post a 2-3 sentence summary back to the user so they can confirm you understood the scope.

---

## Phase 1: Analyze the Current Changes

**Skip if the user passed a `.feature` file.**

Goal: understand what shipped on this branch so the test plan is grounded in actual diffs, not guesses.

1. Run `git status` and `git diff origin/main...HEAD` (or `git diff HEAD` if there are uncommitted-only changes) to see every file touched.
2. Read the changed files in full — not just the diff hunks. Pay special attention to:
   - New routes in `lib/ricqchet_web/router.ex` (user-visible surfaces and API endpoints)
   - New or changed LiveViews (`lib/ricqchet_web/live/`) and controllers (`lib/ricqchet_web/controllers/`)
   - New context functions (`lib/ricqchet/<context>/`) and the data they read/write
   - New Oban workers or queues (delivery, batch, DLQ notification)
   - Channels (`lib/ricqchet_web/channels/`) and any pubsub behavior
   - Schema changes — new Ecto migrations in `priv/repo/migrations/`
   - Any TDD in `docs/` (e.g. `docs/tdd-channels.md`) whose subject matches the branch — read it for intended behavior and acceptance criteria
3. Write a 3-5 bullet summary of what the feature does, who uses it (tenant admin via the dashboard? an API client via an API key?), and what the user-visible or API entry point is. Show this summary to the user before moving on.

If the diff is empty or unrelated to observable behavior (pure refactors, dependency bumps, formatting), stop and tell the user — QA doesn't apply.

---

## Phase 2: Write Gherkin Scenarios

**Skip if the user passed a `.feature` file.** The user has already authored the scenarios; do not rewrite or "improve" them.

Goal: a `.feature` file the user can read and approve before any test code is written.

### Where to put it

`qa/YYYYMMDD-<short-slug>/<feature-slug>.feature` — use today's date. Create the directory if it doesn't exist.

### How to write the scenarios

Standard Gherkin (`Feature` / `Background` / `Scenario` / `Given` / `When` / `Then` / `And`). Aim for 4-8 scenarios covering:

- **Happy path** — the primary journey works end-to-end (e.g. publish a message → it's accepted → delivery is enqueued; or open the dashboard → the new stat renders)
- **Multi-tenant isolation** — a user/API key scoped to tenant A cannot see or act on tenant B's data
- **Auth boundaries** — an unauthenticated request is rejected; the dashboard redirects to `/login`; the API returns 401; an invalid/expired API key or JWT is refused
- **Validation / error states** — invalid input, missing required fields, payload too large, conflicting state; the caller gets a meaningful error and nothing is corrupted
- **Edge cases inferred from the diff** — anything the code branches on (empty lists, single vs. batch, retry/backoff paths, DLQ routing, soft-deleted or inactive records)

Anchor each step to something concrete in the UI or API. Prefer "When I POST to `/v1/messages` with a 2 MB body" over "When I send a big message." Use real seed values that Phase 3 will create so scenarios and setup stay in sync.

Include a `Background:` block for setup that's identical across scenarios (tenant + user/API key, authentication, navigation to the feature root).

### Approval gate

Show the user the file path and the full feature contents in chat. Ask: **"Does this cover what you want QA to verify? Anything to add, remove, or rephrase?"** Wait for explicit approval before continuing. Edits at this stage are cheap; edits after the tests are written are expensive.

---

## Phase 3: Map Scenarios to Test Surfaces and Plan the Data

Goal: decide, per scenario, which test case type encodes it and exactly what data each `Given` requires.

### Step 3a — Pick the right test surface per scenario

| Scenario touches… | Encode with… | Case template |
|---|---|---|
| The LiveView dashboard (`/dashboard`, `/applications`, `/team`) | `Phoenix.LiveViewTest` (`live/2`, `render_click`, `render_submit`, `element/2`, `has_element?/2`) | `RicqchetWeb.ConnCase` |
| The JSON API (`/v1/...`) | `Phoenix.ConnTest` request tests (`get`/`post`/`put`/`delete` + `json_response/2`) | `RicqchetWeb.ConnCase` |
| Realtime channels / pubsub | `Phoenix.ChannelTest` | `Ricqchet.ChannelCase` |
| Pure delivery/retry/DLQ logic or a context function | direct context calls + `Oban.Testing` assertions (`assert_enqueued`) | `Ricqchet.DataCase` |

A single feature often spans more than one surface (e.g. "publish via the API, then see the count update on the dashboard"). Split those into separate scenarios/tests rather than forcing one case to do everything.

### Step 3b — Plan the seed data (in-test, via the sandbox)

There is **no persistent dev-DB seeding** for QA. Every test seeds its own data inside `setup`/`setup_all`, and the SQL sandbox (`Ricqchet.DataCase.setup_sandbox/1`, already wired into `ConnCase`/`DataCase`/`ChannelCase`) rolls it all back after each test. This makes re-runs trivially idempotent — no `ON CONFLICT`, no cleanup phase, no unique-key juggling.

For each `Given` clause, identify the rows it implies and prefer existing helpers over hand-rolled inserts:

- **Tenant + application + API key** (for API-key-authenticated endpoints, e.g. publishing messages): use `create_tenant_with_api_key/3` from `Ricqchet.DataCase`. It returns `%{tenant, application, api_key}` with the plaintext key in `api_key.api_key`.
- **A verified user + JWT** (for the dashboard and JWT-authenticated `/v1` endpoints): register and verify like the controller tests do —
  ```elixir
  {:ok, %{user: _u, verification_token: token}} =
    Auth.register_user(%{
      "email" => "qa-#{System.unique_integer()}@example.com",
      "password" => "secure_password_123",
      "tenant_name" => "QA Org #{System.unique_integer()}"
    })
  {:ok, user} = Auth.verify_email(token)
  {:ok, access_token, _claims} = Ricqchet.Auth.Token.generate_access_token(user)
  ```
- **Messages / batches / DLQ entries / channels**: call the context functions (`Ricqchet.Messages`, `Ricqchet.Batches`, `Ricqchet.DLQ`, `Ricqchet.Channels`) rather than `Repo.insert` raw structs — they set defaults, associations, and side effects you'd otherwise miss.
- **Multi-tenant isolation scenarios**: create two tenants and assert that tenant A's credentials cannot reach tenant B's records.

If a `Given` is genuinely hard to fabricate (e.g. "a message that has exhausted its retries"), prefer setting up the prerequisites and driving the state change through the same context/worker the app uses, then assert on the result. Call this out in a comment at the top of the test.

### Step 3c — Authenticating the connection in tests

- **Dashboard LiveView** (session-based): set `user_id` in the session, then mount.
  ```elixir
  conn = conn |> Plug.Test.init_test_session(%{"user_id" => user.id})
  {:ok, view, _html} = live(conn, ~p"/dashboard")
  ```
  An unauthenticated mount redirects to `/login` — assert that for the auth-boundary scenario:
  ```elixir
  assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/dashboard")
  ```
- **JWT-authenticated API** (`/v1/users`, `/v1/tenant`, `/v1/applications`, `/v1/stats`, …): `put_req_header(conn, "authorization", "Bearer #{access_token}")`.
- **API-key-authenticated API** (message publishing / relay endpoints): `put_req_header(conn, "authorization", "Bearer #{api_key.api_key}")`.

---

## Phase 4: Implement and Run the Scenario Tests

Goal: turn each approved scenario into a runnable test and execute the suite.

### Where the tests go

Write the QA tests under `qa/YYYYMMDD-<short-slug>/` next to the `.feature` file, named `<feature_slug>_qa_test.exs`, so they're easy to find and prune and don't get mixed into the permanent suite yet. (If the user later wants them kept, Phase "Promote" moves them into `test/`.) Each file is an ordinary ExUnit module — one `describe`/`test` per `Scenario`, with the scenario name as the test name so the mapping back to Gherkin is obvious.

```elixir
defmodule Ricqchet.QA.<Feature>QATest do
  use RicqchetWeb.ConnCase, async: true

  alias Ricqchet.Auth
  # ... seed in setup, one test per Scenario ...
end
```

### Run it

```bash
mix test qa/YYYYMMDD-<short-slug>/<feature_slug>_qa_test.exs
```

- Use `async: true` when the test only touches the sandbox (the default and best case). Drop to `async: false` only if it touches a shared/global resource (e.g. a process-registry-backed rate limiter or a named GenServer).
- If a test needs an external HTTP endpoint (delivery target), stub it with `Bypass`; mock injected behaviours with `Mox`. Never let a QA test make a real outbound request.
- For delivery scenarios, assert the job was enqueued with `assert_enqueued(worker: Ricqchet.Delivery.Worker, args: %{...})` rather than waiting on async execution — or run it inline with `Oban.Testing` if you need the side effect.

If a test fails to compile or a `Given` can't be set up, fix the test — do not weaken an assertion to make it pass. A failing assertion that reflects a real bug is a successful QA outcome; report it, don't paper over it.

---

## Phase 5: Report

When the suite has run, post a summary:

- Pass/fail count, one line per scenario
- For each FAIL: the scenario name, the assertion that failed, observed vs. expected, and the relevant `mix test` output
- A one-line verdict: "Ready to ship" / "Needs fixes — see failures above" / "Inconclusive — see notes"

Do not auto-fix bugs surfaced during QA unless the user explicitly asks. Surface them and let the user decide.

### Common Phoenix.LiveViewTest pitfalls

- **Assert on rendered content, not internal state.** Use `has_element?(view, "[data-role=stat]", "42")` or `render(view) =~ "Demo Application"` — don't reach into socket assigns.
- **Events return the new render.** `html = render_click(element(view, "#refresh"))` — assert on the returned `html`, not a stale handle.
- **Form submits go through `render_submit`** with the params map; check both the success render and the validation-error render for the same form.
- **Navigation/redirects**: `assert_redirect(view, "/login")` or pattern-match the `{:error, {:redirect, …}}` / `{:error, {:live_redirect, …}}` tuple from `live/2` and `render_click`.
- **Flash messages** surface in the rendered HTML after the action — assert on them there.
- **Async assigns / `handle_info`**: if the LiveView loads data asynchronously or via pubsub, the initial render may be empty; use `render_async(view)` or send the expected message and re-render before asserting.

---

## Optional: Promote to the Permanent Suite

**Only offer this if every scenario passed.** A QA pass that revealed bugs should be re-run after fixes, not frozen into the suite.

When the run is green, ask the user — exactly once, in one short message:

> All scenarios passed. Want me to move these into the permanent test suite (`test/ricqchet_web/live/`, `test/ricqchet_web/controllers/`, or `test/ricqchet/<context>/` as appropriate) so they run in CI?

If the user agrees, relocate each test file to the matching directory, rename the module to the conventional `…Test`, and confirm `mix test` still passes from its new home. If the user declines, leave the files under `qa/` and move on.

---

## Cleanup (Optional)

After the user acknowledges the results, ask whether to:

- Delete the `qa/YYYYMMDD-<short-slug>/` artifacts (the `.feature` file and QA test) — some users keep them for the PR description; others toss them.
- Keep them if they're being promoted to the permanent suite.

No DB cleanup is needed — the SQL sandbox already rolled back every test's data. Do not silently delete artifacts; the user might want them.

---

## Optional: Manual Exploration

If the user wants to *see* the feature (not just green tests), you can start the dev server for a manual look — this is supplementary, not a replacement for the ExUnit pass:

1. `mix phx.server` (background process; never block the conversation on it). It serves on `http://localhost:4000`; API docs at `/api/docs`.
2. Seed dev data with `mix run priv/repo/seeds.exs` — creates tenant "Demo Organization", user `admin@demo.local` / `password123456`, an application, and an API key (printed once).
3. Tell the user the URL and credentials so they can click through it themselves.

---

## Checklist Before Handing Off

- [ ] Summary of changes (Phase 1) **OR** summary of the provided `.feature` file shown to the user
- [ ] `.feature` file exists and was either authored+approved (Phase 2) or supplied by the user
- [ ] Each scenario mapped to a test surface and its seed data planned (Phase 3)
- [ ] QA test(s) written under `qa/YYYYMMDD-<slug>/` and run with `mix test`
- [ ] Pass/fail report posted to chat, one line per scenario (Phase 5)
- [ ] If all scenarios passed, offered (once) to promote them into the permanent suite — and honored the user's choice
