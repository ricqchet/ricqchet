# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0](https://github.com/doomspork/ricqchet/compare/typescript-client-v0.1.0...typescript-client-v0.2.0) (2026-01-31)


### Features

* **typescript-client:** add typescript client library ([8da4e53](https://github.com/doomspork/ricqchet/commit/8da4e53f074fb58432d1d5709ef525faf75e9345))

## [0.1.0] - Unreleased

### Added

- Initial release
- `RicqchetClient` class for API operations
- Support for publish, fan-out, getMessage, cancelMessage operations
- `verifySignature` and `verifyRequest` functions for webhook verification
- HMAC-SHA256 signature verification with timing-safe comparison
- TypeScript type definitions
