# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- Initial release
- `Ricqchet.Client` macro for defining client modules
- `Ricqchet.Verification` macro for webhook signature verification
- Support for publish, fan-out, get_message, cancel_message operations
- HMAC-SHA256 signature verification
- Configuration via environment variables with `{:system, "ENV_VAR"}` syntax
