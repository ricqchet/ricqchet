# Changelog

## [0.1.1](https://github.com/doomspork/ricqchet/compare/v0.1.0...v0.1.1) (2026-01-31)


### Features

* add api key authentication ([b3190a9](https://github.com/doomspork/ricqchet/commit/b3190a95c09d6f0939cf351bfc232c7b3994f211))
* add batch delivery feature ([a511527](https://github.com/doomspork/ricqchet/commit/a51152728e67795ac0dcd9d1250fc1a72e39a8b8))
* add message delivery with retries ([0d87e11](https://github.com/doomspork/ricqchet/commit/0d87e116c2a55838dbf461f29199791c80f8d21d))
* add message status endpoints ([38b3586](https://github.com/doomspork/ricqchet/commit/38b3586d42f49870f4e17813e40cc862918949cf))
* add publish endpoint ([5521dba](https://github.com/doomspork/ricqchet/commit/5521dba4abc2916e3c98e372e8e1eb1dcbfb34af))
* add tenants and messages schemas ([544d77b](https://github.com/doomspork/ricqchet/commit/544d77be21da1300cfd2acd1af8bf124afb57a07))
* **api:** add fan-out support for multi-destination publishing ([575563e](https://github.com/doomspork/ricqchet/commit/575563e0c8ebc1d22893aceb7d0f4cddf132abb8))
* **api:** add openapi documentation with open_api_spex ([2f9b780](https://github.com/doomspork/ricqchet/commit/2f9b78094d017e24752f0c0a8dd8eb36b845fa52))
* **schema:** restructure multi-tenant schema with applications and api keys ([1e855c8](https://github.com/doomspork/ricqchet/commit/1e855c82f0058b84509ca64b80712ccae6fcc56b))


### Bug Fixes

* address copilot feedback issues ([03a6a97](https://github.com/doomspork/ricqchet/commit/03a6a97d490eeaff58a2a80c0992284d0cc16131))
* address copilot feedback issues ([40b61db](https://github.com/doomspork/ricqchet/commit/40b61dbf3c0f34911cbd6ad6e6c059382ebe0711))
* **api:** address copilot review feedback ([2afd846](https://github.com/doomspork/ricqchet/commit/2afd84671f432c18fe44c3371bcfcefb925c566c))
* **api:** handle deduplication race condition gracefully ([91f82d8](https://github.com/doomspork/ricqchet/commit/91f82d8041a1355a008ba1f3071f0d8b94d1c9c6))
* **ci:** add ex_unit to dialyzer plt_add_apps ([9867cee](https://github.com/doomspork/ricqchet/commit/9867ceeda2837e780636a982f4273b59a9380bdc))
* **ci:** add permissions for commitlint to access pr commits ([d3f44d6](https://github.com/doomspork/ricqchet/commit/d3f44d6a6c327da3771d81b3ceba641445bb66af))
* improve error handling, backpressure, and batch status clarity ([05ec420](https://github.com/doomspork/ricqchet/commit/05ec420508a8eb815632dccdab49933d029bddc1))
* resolve credo and dialyzer warnings ([6d628dc](https://github.com/doomspork/ricqchet/commit/6d628dc5cac0528e12d1ee9b9c5ef92e0296ec5a))
* **security:** add rate limiting, body size limits, and header validation ([dbc0f21](https://github.com/doomspork/ricqchet/commit/dbc0f21d0e6facd782212224aba17222eed1df9b))
* **security:** add ssrf protection and safe http method conversion ([ae76cc3](https://github.com/doomspork/ricqchet/commit/ae76cc346c72aa85dac9140f8dccbe7f81c28044))


### Performance Improvements

* **auth:** optimize api key lookup with prefix index ([7c266d9](https://github.com/doomspork/ricqchet/commit/7c266d95b771110202d7267744292c28e8f2ee87))
