# Changelog

## [0.2.0](https://github.com/ricqchet/ricqchet/compare/ricqchet-v0.1.0...ricqchet-v0.2.0) (2026-06-08)


### ⚠ BREAKING CHANGES

* **dlq:** messages and batches now belong to applications

### Features

* add api key authentication ([b3190a9](https://github.com/ricqchet/ricqchet/commit/b3190a95c09d6f0939cf351bfc232c7b3994f211))
* add batch delivery feature ([a511527](https://github.com/ricqchet/ricqchet/commit/a51152728e67795ac0dcd9d1250fc1a72e39a8b8))
* add batch event publishing endpoint ([2e0a8d5](https://github.com/ricqchet/ricqchet/commit/2e0a8d524f301c475fcbb2c9a5cb2d4f7f21a597))
* add browser-safe subscribe-only api key scope ([#129](https://github.com/ricqchet/ricqchet/issues/129)) ([0558e7f](https://github.com/ricqchet/ricqchet/commit/0558e7f8a0752690b35e4a2eee4c6e4155620fbb))
* add cache channel support ([167f6f0](https://github.com/ricqchet/ricqchet/commit/167f6f0828cb77ce0bf14d32e5d94cedcf6ec3d2))
* add channel events history api endpoint ([1e0d48b](https://github.com/ricqchet/ricqchet/commit/1e0d48b4f26d9de49ac70ce864d0f4a0ebdbf9cb))
* add channel events history cleanup worker ([f144ea8](https://github.com/ricqchet/ricqchet/commit/f144ea898cd06eb128b6402a749838e41cf06591))
* add channel members api endpoint ([52f8df5](https://github.com/ricqchet/ricqchet/commit/52f8df5713fe8601c6bed113baa03837a493820a))
* add channel namespace crud controller and routes ([e98f861](https://github.com/ricqchet/ricqchet/commit/e98f8612fb2d5abdf05a227ad6ea3023150952b7))
* add channel telemetry, metrics, and event size limits ([4502643](https://github.com/ricqchet/ricqchet/commit/4502643bb0989e8063ae2bc320a609aa2c9ecacb))
* add channels auth module for private channel authorization ([31c43f4](https://github.com/ricqchet/ricqchet/commit/31c43f410804464ec0ffbdcd60281cef1040004f))
* add client events with rate limiting ([ad87336](https://github.com/ricqchet/ricqchet/commit/ad8733620a8d342acf3b62c53ee756b02a257120))
* add conditional event persistence to event publisher ([7b5b833](https://github.com/ricqchet/ricqchet/commit/7b5b83384b38ab5b92a95dd053e151f2a744f2b1))
* add connection management and limits ([2acbc18](https://github.com/ricqchet/ricqchet/commit/2acbc1805256b9a175290c731958180c2f1d46ca))
* add dashboard metrics and real-time activity ([#92](https://github.com/ricqchet/ricqchet/issues/92)) ([0b876b7](https://github.com/ricqchet/ricqchet/commit/0b876b72c297400615ec50693c4c5643fc935434))
* add flop for pagination, filtering, and sorting ([#88](https://github.com/ricqchet/ricqchet/issues/88)) ([98a1595](https://github.com/ricqchet/ricqchet/commit/98a15953da2c6cfe65cbb650ce5f1e3d943b9607))
* add lifecycle and presence webhooks ([1da5abc](https://github.com/ricqchet/ricqchet/commit/1da5abc77a15cdcaa22389231419777b29f652c8))
* add message delivery with retries ([0d87e11](https://github.com/ricqchet/ricqchet/commit/0d87e116c2a55838dbf461f29199791c80f8d21d))
* add message relay to channels integration ([1eb9b1f](https://github.com/ricqchet/ricqchet/commit/1eb9b1f95d4d8ceae05a59d2a74b32bf2243edd4))
* add message status endpoints ([38b3586](https://github.com/ricqchet/ricqchet/commit/38b3586d42f49870f4e17813e40cc862918949cf))
* add missed-message recovery on channel rejoin ([d92bc25](https://github.com/ricqchet/ricqchet/commit/d92bc25778920d83e6e1783270814825ede43af2))
* add multi-node pubsub support for channel counts ([e08d52a](https://github.com/ricqchet/ricqchet/commit/e08d52ad539111d20b0e42ecd3278082a183f65a))
* add namespace cache with ets and config lookup ([94886a7](https://github.com/ricqchet/ricqchet/commit/94886a740e83462d2d79b32e2671e8c7e70543e4))
* add namespaces context with crud and pattern matching ([c06d7f9](https://github.com/ricqchet/ricqchet/commit/c06d7f9970a4d8619d4c2a78ed10d0b10674ba65))
* add phoenix liveview ui to replace react spa ([#124](https://github.com/ricqchet/ricqchet/issues/124)) ([0dd02f4](https://github.com/ricqchet/ricqchet/commit/0dd02f4b7a863b224d85c55f71c09f01837f0da3))
* add phoenix presence tracking for presence channels ([6091fad](https://github.com/ricqchet/ricqchet/commit/6091fadeb900e44e14a93d52d982cc2cc34168e5))
* add private channel authorization to pubsub channel ([c3f6ad9](https://github.com/ricqchet/ricqchet/commit/c3f6ad9d2d984fdc4cc125feb28351f2e4418fc2))
* add publish endpoint ([5521dba](https://github.com/ricqchet/ricqchet/commit/5521dba4abc2916e3c98e372e8e1eb1dcbfb34af))
* add seed file for dev database setup ([#93](https://github.com/ricqchet/ricqchet/issues/93)) ([d09c9b4](https://github.com/ricqchet/ricqchet/commit/d09c9b4eeaeaf24bebd9b326da180a33a7463187))
* add tenants and messages schemas ([544d77b](https://github.com/ricqchet/ricqchet/commit/544d77be21da1300cfd2acd1af8bf124afb57a07))
* add websocket channels phase 1 MVP ([#120](https://github.com/ricqchet/ricqchet/issues/120)) ([76ef2c9](https://github.com/ricqchet/ricqchet/commit/76ef2c96139dd7fca731a45355e2a7e588d9db88))
* **api-keys:** add api key management endpoints ([#86](https://github.com/ricqchet/ricqchet/issues/86)) ([9bd694c](https://github.com/ricqchet/ricqchet/commit/9bd694c44626b0bce931afd3b4586d26643a04a3))
* **api:** add cors configuration for web clients ([#85](https://github.com/ricqchet/ricqchet/issues/85)) ([6a62351](https://github.com/ricqchet/ricqchet/commit/6a6235171a05cf9cb598a40309dd99eeb197f412))
* **api:** add fan-out support for multi-destination publishing ([575563e](https://github.com/ricqchet/ricqchet/commit/575563e0c8ebc1d22893aceb7d0f4cddf132abb8))
* **api:** add get /v1/signing-secret endpoint ([8dbcc8b](https://github.com/ricqchet/ricqchet/commit/8dbcc8b83be93e1eeb8512cb423ee12c4fa50b80))
* **api:** add openapi documentation with open_api_spex ([2f9b780](https://github.com/ricqchet/ricqchet/commit/2f9b78094d017e24752f0c0a8dd8eb36b845fa52))
* **applications:** add application management api ([#82](https://github.com/ricqchet/ricqchet/issues/82)) ([05c9305](https://github.com/ricqchet/ricqchet/commit/05c930578a0225e5e77aa3c59de69be0da49453e))
* **auth:** add change password endpoint ([350af2d](https://github.com/ricqchet/ricqchet/commit/350af2d98ea09d9cca62d983b16a3168bd885200))
* **auth:** add email verification endpoints ([aff7ca2](https://github.com/ricqchet/ricqchet/commit/aff7ca26c9f4ab26bc4b9dcc6d2f29ce8906756a))
* **auth:** add jwt and email infrastructure ([11fbe4b](https://github.com/ricqchet/ricqchet/commit/11fbe4bc54a1863e3f2c85414c408a7e3fd86604))
* **auth:** add login, logout, and token refresh endpoints ([6f82b33](https://github.com/ricqchet/ricqchet/commit/6f82b336f9bcd7a0b29ce1dde1a11461f3741c36))
* **auth:** add password reset and rate limiting endpoints ([#90](https://github.com/ricqchet/ricqchet/issues/90)) ([a174f96](https://github.com/ricqchet/ricqchet/commit/a174f964ccd29450824c2f0c436eb01ff47a6cfc))
* **auth:** add user registration endpoint ([00b78bd](https://github.com/ricqchet/ricqchet/commit/00b78bd86abcc30c536db83f7fe6c14e90ff0010))
* convert to self-hosted single-org model with role-based access ([#126](https://github.com/ricqchet/ricqchet/issues/126)) ([65f4961](https://github.com/ricqchet/ricqchet/commit/65f4961221507e3a9f4d53a5e5f76264b4a778cc))
* **dlq:** add global dlq destination support for applications ([#13](https://github.com/ricqchet/ricqchet/issues/13)) ([1a59cf5](https://github.com/ricqchet/ricqchet/commit/1a59cf54ce77994942262eb0ff0c0dbaf36d9935))
* **elixir-client:** add elixir client library ([e9905d4](https://github.com/ricqchet/ricqchet/commit/e9905d4b704ca1bebb37998014d5ed73d99c3dc6))
* **elixir-client:** add test helpers for client testing ([#79](https://github.com/ricqchet/ricqchet/issues/79)) ([979225f](https://github.com/ricqchet/ricqchet/commit/979225ff6024c61be32f7203aeb4667c92a64f00))
* flow control with parallelism and rate limiting ([#96](https://github.com/ricqchet/ricqchet/issues/96)) ([dfd9338](https://github.com/ricqchet/ricqchet/commit/dfd93387a33be0f7c157f924ff7f95414920ff83))
* **schema:** restructure multi-tenant schema with applications and api keys ([1e855c8](https://github.com/ricqchet/ricqchet/commit/1e855c82f0058b84509ca64b80712ccae6fcc56b))
* **server:** add hmac signature support for delivery verification ([229bb28](https://github.com/ricqchet/ricqchet/commit/229bb280260a44da2fb86b3a291fd5e44bdb86b3))
* simplify channels to bare topic names ([#127](https://github.com/ricqchet/ricqchet/issues/127)) ([b16f2df](https://github.com/ricqchet/ricqchet/commit/b16f2df2fc088aeda26c1558436bc452ba7c6064))
* **tenants:** add team management endpoints ([#91](https://github.com/ricqchet/ricqchet/issues/91)) ([99de61a](https://github.com/ricqchet/ricqchet/commit/99de61ae2f1eb6836f6025a6fa2d7f4075e0da9f))
* **typescript-client:** add typescript client library ([8da4e53](https://github.com/ricqchet/ricqchet/commit/8da4e53f074fb58432d1d5709ef525faf75e9345))
* **users:** add user profile endpoints ([c1f0710](https://github.com/ricqchet/ricqchet/commit/c1f0710a3975e345e6dbfc95129ad6b3c759977a))


### Bug Fixes

* address copilot feedback issues ([03a6a97](https://github.com/ricqchet/ricqchet/commit/03a6a97d490eeaff58a2a80c0992284d0cc16131))
* address copilot feedback issues ([40b61db](https://github.com/ricqchet/ricqchet/commit/40b61dbf3c0f34911cbd6ad6e6c059382ebe0711))
* address copilot review feedback ([5e0e94b](https://github.com/ricqchet/ricqchet/commit/5e0e94b35e2111ee7ae94faaabf85bd68d2b645d))
* align websocket activity events with frontend expected format ([#98](https://github.com/ricqchet/ricqchet/issues/98)) ([eec3935](https://github.com/ricqchet/ricqchet/commit/eec393551a34ccfef07315ce5176d28540edd782))
* **api:** address copilot review feedback ([2afd846](https://github.com/ricqchet/ricqchet/commit/2afd84671f432c18fe44c3371bcfcefb925c566c))
* **api:** handle deduplication race condition gracefully ([91f82d8](https://github.com/ricqchet/ricqchet/commit/91f82d8041a1355a008ba1f3071f0d8b94d1c9c6))
* **auth:** address code review issues in jwt auth implementation ([23c4ff2](https://github.com/ricqchet/ricqchet/commit/23c4ff215258fe052ea8c451e7711f38523c51a5))
* **ci:** add ex_unit to dialyzer plt_add_apps ([9867cee](https://github.com/ricqchet/ricqchet/commit/9867ceeda2837e780636a982f4273b59a9380bdc))
* **ci:** add permissions for commitlint to access pr commits ([d3f44d6](https://github.com/ricqchet/ricqchet/commit/d3f44d6a6c327da3771d81b3ceba641445bb66af))
* **ci:** remove conflicting release-please version bump config ([da4a6e5](https://github.com/ricqchet/ricqchet/commit/da4a6e5fafbe2dc236396155924c17f3a872f121))
* correct websocket auth claim key and add phoenix code reloader listener ([#95](https://github.com/ricqchet/ricqchet/issues/95)) ([8969bea](https://github.com/ricqchet/ricqchet/commit/8969beaaae53ac3e275a341e9d8dbc6db25d846f))
* improve error handling, backpressure, and batch status clarity ([05ec420](https://github.com/ricqchet/ricqchet/commit/05ec420508a8eb815632dccdab49933d029bddc1))
* make seed file idempotent for reruns ([#97](https://github.com/ricqchet/ricqchet/issues/97)) ([84ea19f](https://github.com/ricqchet/ricqchet/commit/84ea19f546e7de45b7411e8bda467aa098acd769))
* **openapi:** add missing putapispec plug to pipeline ([#89](https://github.com/ricqchet/ricqchet/issues/89)) ([ab4a804](https://github.com/ricqchet/ricqchet/commit/ab4a804378f8294a6c9dafcf831336ba7c38a1d8))
* resolve credo and dialyzer warnings ([6d628dc](https://github.com/ricqchet/ricqchet/commit/6d628dc5cac0528e12d1ee9b9c5ef92e0296ec5a))
* **security:** add rate limiting, body size limits, and header validation ([dbc0f21](https://github.com/ricqchet/ricqchet/commit/dbc0f21d0e6facd782212224aba17222eed1df9b))
* **security:** add ssrf protection and safe http method conversion ([ae76cc3](https://github.com/ricqchet/ricqchet/commit/ae76cc346c72aa85dac9140f8dccbe7f81c28044))
* **server:** update signer spec to allow nil timestamp ([a306b33](https://github.com/ricqchet/ricqchet/commit/a306b33266235f62423c24919adbeb075ab0797c))
* verify seed user email so admin can log in ([#94](https://github.com/ricqchet/ricqchet/issues/94)) ([5c010a0](https://github.com/ricqchet/ricqchet/commit/5c010a05e23843151a58f999a24a2f8a73b260e6))


### Performance Improvements

* **auth:** optimize api key lookup with prefix index ([7c266d9](https://github.com/ricqchet/ricqchet/commit/7c266d95b771110202d7267744292c28e8f2ee87))
