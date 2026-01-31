# Changelog

## [0.2.0](https://github.com/doomspork/ricqchet/compare/server-v0.1.0...server-v0.2.0) (2026-01-31)


### ⚠ BREAKING CHANGES

* **dlq:** messages and batches now belong to applications

### Features

* **api:** add get /v1/signing-secret endpoint ([8dbcc8b](https://github.com/doomspork/ricqchet/commit/8dbcc8b83be93e1eeb8512cb423ee12c4fa50b80))
* **dlq:** add global dlq destination support for applications ([#13](https://github.com/doomspork/ricqchet/issues/13)) ([1a59cf5](https://github.com/doomspork/ricqchet/commit/1a59cf54ce77994942262eb0ff0c0dbaf36d9935))
* **server:** add hmac signature support for delivery verification ([229bb28](https://github.com/doomspork/ricqchet/commit/229bb280260a44da2fb86b3a291fd5e44bdb86b3))


### Bug Fixes

* **server:** update signer spec to allow nil timestamp ([a306b33](https://github.com/doomspork/ricqchet/commit/a306b33266235f62423c24919adbeb075ab0797c))
