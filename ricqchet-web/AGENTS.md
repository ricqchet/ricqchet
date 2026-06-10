# AGENTS.md

Ricqchet is an HTTP message relay service with guaranteed delivery, retries, fan-out, batching, and scheduling. It is built with Phoenix 1.8 (JSON API + LiveView dashboard) and Oban for job processing.

> **Monorepo:** this is the server subproject (`ricqchet-web/`) of the [Ricqchet monorepo](../AGENTS.md). Run all `mix` commands and resolve every relative path in this file from inside `ricqchet-web/`. The TypeScript client lives in `../ricqchet-ts-client/`.

## Quick Reference

```bash
mix setup              # Install deps, create DB, run migrations
mix phx.server         # Start dev server (API docs at /api/docs)
mix test               # Run tests
mix test --failed      # Re-run failed tests only
mix precommit          # Required before committing
```

## Deployment and Access Model

Ricqchet is **self-hosted and single-organization** with one hidden default tenant per instance.

- **No public sign-up.** The first admin is created on first run from `ADMIN_EMAIL` / `ADMIN_PASSWORD` or a generated password via `Ricqchet.Release.bootstrap/0`, called by `priv/repo/seeds.exs`. Recovery: `mix ricqchet.reset_admin_password [email]`.
- **Admins add users directly** with `POST /v1/tenant/users` or the Team page. There are no email invitations.
- **Roles** are defined by `Ricqchet.Authorization`, the single source of truth: `admin` (full access, users, settings), `member` (create/edit apps, API keys, channels), and `viewer` (read-only). Use `Authorization.authorize/2` in controllers, `require_editor` / `require_admin` in LiveViews, and `can?/2` in templates. Role checks apply to JWT/session surfaces, **not** API-key relay endpoints.

## Before Committing

Run the precommit alias before every commit:

```bash
mix precommit
```

This runs, in order:

1. `compile --warnings-as-errors` - no compiler warnings
2. `deps.unlock --unused` - clean unused dependencies
3. `format` - auto-format code
4. `credo --strict` - static analysis
5. `dialyzer` - type checking
6. `test` - all tests pass

Do not commit if any step fails.

## Commit Conventions

This project uses [conventional commits](https://www.conventionalcommits.org/) enforced by commitlint.

- Format: `type: description` or `type(scope): description`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
- Messages must be lowercase
- Header max length is 100 characters
- Never include `Co-authored By`

Examples:

```text
feat: add message deduplication support
fix: correct retry backoff calculation
docs: update api reference for fan-out
refactor(delivery): extract retry logic to module
```

## Documentation Requirements

The `docs/` folder contains user-facing documentation. Update docs when making changes that affect:

- API endpoints or request/response formats -> `docs/api-reference.md`
- Authentication or API keys -> `docs/authentication.md`
- Batching behavior -> `docs/batching.md`
- Configuration options -> `docs/configuration.md`
- Delivery, retries, or timeouts -> `docs/delivery.md`
- Core concepts or architecture -> `docs/overview.md`
- Webhook consumer guidance -> `docs/receiving-webhooks.md`

Keep the main `README.md` in sync for major feature additions.

## Project Structure

```text
lib/
├── ricqchet/              # Core business logic (contexts)
│   ├── delivery/          # Message delivery (workers, HTTP client)
│   ├── messages/          # Message context
│   ├── batches/           # Batch message logic
│   ├── dlq/               # Dead letter queue
│   ├── applications/      # Application management
│   ├── api_keys/          # API key management
│   ├── auth/              # JWT authentication
│   ├── tenants/           # Multi-tenancy
│   └── users/             # User management
├── ricqchet.ex            # Public API facade
├── ricqchet_web/          # Phoenix controllers, routes, plugs
│   ├── controllers/       # JSON API controllers
│   ├── plugs/             # Authentication, rate limiting
│   ├── schemas/           # OpenAPI schema definitions
│   └── telemetry.ex       # Telemetry metrics
└── ricqchet_web.ex        # Web module helpers
```

## Key Dependencies

- **Req** - HTTP client. Use the already included `Req` library for HTTP requests; avoid `:httpoison`, `:tesla`, and `:httpc`.
- **Oban** - Background job processing
- **OpenApiSpex** - API documentation at `/api/docs`
- **Joken** - JWT token handling
- **Argon2** - Password hashing

## Structured Logging

Use `Logger` with structured metadata instead of string interpolation for better observability:

```elixir
require Logger

# Good: structured metadata
Logger.info("Message delivered", message_id: message.id, status: status)
Logger.warning("Delivery failed", message_id: message.id, reason: inspect(reason))

# Avoid: harder to query
Logger.info("Message #{message.id} delivered with status #{status}")
```

Available metadata configured in `config/config.exs`:

- `:request_id` - auto-populated from `Plug.RequestId`

Add domain-specific metadata when logging in workers and contexts:

- `:message_id`, `:batch_id` - delivery operations
- `:tenant_id`, `:application_id` - multi-tenant context
- `:user_id` - user operations

## Telemetry and Metrics

Custom metrics are defined in `lib/ricqchet_web/telemetry.ex`. The project uses `Telemetry.Metrics` with periodic polling.

Existing metrics:

- Phoenix endpoint/router timing
- Ecto query timing: total, decode, query, queue, idle
- VM memory and run queue lengths

When adding custom metrics:

1. Emit telemetry events in your code:

   ```elixir
   :telemetry.execute(
     [:ricqchet, :delivery, :complete],
     %{duration: duration_ms},
     %{status: :success, message_id: message.id}
   )
   ```

2. Add metric definitions in `telemetry.ex`:

   ```elixir
   summary("ricqchet.delivery.complete.duration",
     tags: [:status],
     unit: {:native, :millisecond}
   )
   ```

Oban emits telemetry events automatically for job execution. See the Oban telemetry docs when wiring job metrics.

## Oban Queues

Configured queues in `config/config.exs`:

- `delivery: 50` - message delivery jobs
- `dlq_notifications: 10` - dead letter queue webhook notifications

Workers:

- `Ricqchet.Delivery.Worker` - single message delivery
- `Ricqchet.Delivery.BatchWorker` - batch delivery
- `Ricqchet.DLQ.NotificationWorker` - DLQ notifications

## Testing

```bash
mix test                    # Run all tests
mix test path/to/test.exs   # Run specific file
mix test --failed           # Re-run failed tests
```

- Use `Mox` for mocking and `Bypass` for HTTP stubbing.
- Always use `start_supervised!/1` to start processes in tests so cleanup is guaranteed.
- Avoid `Process.sleep/1` and `Process.alive?/1` in tests.
- To wait for a process to finish, use `Process.monitor/1` and assert on the `DOWN` message:

  ```elixir
  ref = Process.monitor(pid)
  assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
  ```

- To synchronize before the next call, use `_ = :sys.get_state/1` to ensure the process has handled prior messages.

## Phoenix 1.8 Guidelines

- Always begin LiveView templates with `<Layouts.app flash={@flash} ...>`, which wraps all inner content.
- The `RicqchetWeb.Layouts` module is aliased in `ricqchet_web.ex`, so use it without adding another alias.
- If you see errors about a missing `current_scope` assign, move routes to the proper `live_session` and pass `current_scope` to `<Layouts.app>` as needed.
- Phoenix 1.8 moved `<.flash_group>` to the `Layouts` module. Do not call `<.flash_group>` outside `layouts.ex`.
- Use the imported `<.icon name="hero-x-mark" class="w-5 h-5" />` component for Hero icons. Do not use `Heroicons` modules or similar.
- Use the imported `<.input>` component from `core_components.ex` for form inputs when available.
- If you override default input classes with `<.input class="...">`, no default classes are inherited; custom classes must fully style the input.
- Router `scope` blocks include an optional alias prefixed for all routes inside the scope. Be mindful of this to avoid duplicate module prefixes.
- Do not create route aliases that are already provided by the scope:

  ```elixir
  scope "/admin", RicqchetWeb.Admin do
    pipe_through :browser

    live "/users", UserLive, :index
  end
  ```

  This route points to `RicqchetWeb.Admin.UserLive`.

- `Phoenix.View` is no longer needed or included with Phoenix. Do not use it.

## Elixir Guidelines

- Elixir lists do not support index-based access with access syntax:

  ```elixir
  # Invalid
  i = 0
  mylist = ["blue", "green"]
  mylist[i]

  # Valid
  Enum.at(mylist, i)
  ```

- Variables are immutable but can be rebound. For block expressions such as `if`, `case`, and `cond`, bind the result of the expression instead of rebinding inside it:

  ```elixir
  # Invalid: result is not assigned
  if connected?(socket) do
    socket = assign(socket, :val, val)
  end

  # Valid
  socket =
    if connected?(socket) do
      assign(socket, :val, val)
    end
  ```

- Never nest multiple modules in the same file; it can cause cyclic dependencies and compilation errors.
- Never use map access syntax such as `changeset[:field]` on structs. Access fields directly (`my_struct.field`) or use higher-level APIs such as `Ecto.Changeset.get_field/2`.
- Use Elixir's standard `Time`, `Date`, `DateTime`, and `Calendar` modules for date and time manipulation. Do not add date/time dependencies unless asked or for date/time parsing, where `date_time_parser` is acceptable.
- Do not use `String.to_atom/1` on user input.
- Predicate function names should end in `?` and should not start with `is_`; reserve `is_*` names for guards.
- OTP primitives such as `DynamicSupervisor` and `Registry` require names in child specs, such as `{DynamicSupervisor, name: Ricqchet.DynamicSup}`. Use that name with APIs such as `DynamicSupervisor.start_child/2`.
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. Usually pass `timeout: :infinity`.

## Mix Guidelines

- Read task docs and options before using tasks: `mix help task_name`.
- To debug test failures, run a specific file with `mix test test/my_test.exs` or all previously failed tests with `mix test --failed`.
- `mix deps.clean --all` is almost never needed. Avoid it unless you have a good reason.

## Ecto Guidelines

- Always preload associations in queries when they will be accessed in templates, such as `message.user.email`.
- Remember `import Ecto.Query` and other supporting modules when writing `seeds.exs`.
- `Ecto.Schema` fields always use the `:string` type, even for `:text` columns, for example `field :name, :string`.
- `Ecto.Changeset.validate_number/2` does not support `:allow_nil`. Ecto validations only run if a change for the field exists and the value is not nil, so that option is unnecessary.
- Use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields.
- Fields set programmatically, such as `user_id`, must not be listed in `cast` calls. Set them explicitly when creating the struct.
- Always use `mix ecto.gen.migration migration_name_using_underscores` when generating migration files so the correct timestamp and conventions are applied.
