# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0](https://github.com/doomspork/ricqchet/compare/elixir-client-v0.1.0...elixir-client-v0.2.0) (2026-01-31)


### Features

* **elixir-client:** add elixir client library ([e9905d4](https://github.com/doomspork/ricqchet/commit/e9905d4b704ca1bebb37998014d5ed73d99c3dc6))
* **elixir-client:** add test helpers for client testing ([#79](https://github.com/doomspork/ricqchet/issues/79)) ([979225f](https://github.com/doomspork/ricqchet/commit/979225ff6024c61be32f7203aeb4667c92a64f00))

## [0.1.0] - Unreleased

### Added

- Initial release
- `Ricqchet.Client` macro for defining client modules
- `Ricqchet.Verification` macro for webhook signature verification
- Support for publish, fan-out, get_message, cancel_message operations
- HMAC-SHA256 signature verification
- Configuration via environment variables with `{:system, "ENV_VAR"}` syntax
