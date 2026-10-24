## 0.2.3

* Docs only, no code change: `README.md` aligned with the wire
  contract and the companion source (stable `?b=` bucket persistence /
  `<prefix>.<env>.bucket` fallback / `clearBucket`,
  `?userHash=` / `?country=` accepted-but-ignored deprecation, fixed
  pure-Dart client link). Requires `configwire ^0.3.2` or later.

## 0.2.2

* Backward compatible with 0.2.x: no migration needed — old calls
  compile and behave as before. `ConfigWireFlutter.createConfigWire`
  is restored (deprecated, use your own `ConfigWire` +
  `cw.configureFlutter()` instead), and `configureFlutter` accepts the
  legacy `prefs:` / `prefixCache:` args again (deprecated, use `store:`
  with `SharedPreferencesCacheStore` instead). An explicit legacy
  `prefs:` or non-default `prefixCache:` still governs the install-ID
  key verbatim, and non-prefs stores keep the 0.2.x stable ID via the
  prefs fallback instead of going anonymous — existing
  `<prefix>.<env>.userId` keys are adopted as-is, no reshuffle.
* Added: `configureFlutter` gains `store: CacheStore?` (explicit
  `store:` param > explicit ctor store > auto-attached
  `SharedPreferencesCacheStore(env: cw.env)` honoring legacy
  `prefs:`/`prefixCache:`), so a bare `ConfigWire(...)` plus
  `configureFlutter()` gets disk persistence and a stable install ID.
  Stable install IDs via the `user_store` helpers
  (`loadPersistedUserId` / `savePersistedUserId` /
  `clearPersistedUserId` / `userIdKeyFor` / `defaultIdGenerator` /
  `generateUserId`, deprecations lifted) running on the store-owned
  backend (`SharedPreferencesCacheStore.prefs`). Only
  `?userHash=<sha256hex16>` leaves the device; the server ignores
  `userHash` for bucketing/exposure identity (accepted-but-ignored,
  `X-CW-Deprecated-userHash` compat header stamped) and buckets from
  its daily anonID unless a valid `?b=` overrides it.
* Stable bucket `?b=`: the companion persists the server-minted `bucket`
  first-write-wins (prefs fallback keeps the 0.2.x stable ID instead of
  going anonymous) and sends it as `?b=` on fetch and events, so
  bucketing survives daily anonID rotation.

## 0.2.1

* Bring-your-own `ConfigWire.configureFlutter(...)` extension
  (`lib/src/configwire_flutter.dart`): construct your own `ConfigWire`
  with a `SharedPreferencesCacheStore`, then
  `await cw.configureFlutter(...)` resolves the install ID + device
  targeting, calls `cw.setTargeting`, and optionally runs
  `cw.ensureInitialized()`. Targeting resolves once per instance
  (first-call-wins; concurrent callers join the in-flight future and
  later callers no-op) and never throws (persisted-ID I/O swallowed,
  throwing custom collectors degrade to identity-only). Like the core
  constructor, configuring never fetches by default
  (`ensureInitialized: false` — targeting only, hermetic); pass `true`
  or call `cw.ensureInitialized()` afterwards for the cache load plus
  forced fetch. `ConfigWireFlutter.createConfigWire` is deprecated —
  construct `ConfigWire` directly instead (note the default flip: it
  fetches unless `ensureInitialized: false`, while `configureFlutter`
  only targets unless `ensureInitialized: true`).
* `SharedPreferencesCacheStore` prefs now optional
  (`lib/src/prefs_store.dart`): defaults to `SharedPreferencesAsync()`.
  When callers supply their own `ConfigWire` with a cache store, the
  `prefixCache`/`prefs` passed to `configureFlutter` must match the
  store's so the userId key lines up with `cw.env`.
* Example + docs migrated to the new flow (`example/lib/init_gate.dart`,
  `example/main.dart`, `README.md`); new hermetic suite for the
  bring-your-own flow (`test/flutter_init_test.dart`).

## 0.2.0

* **Breaking:** fetch identity is now userHash-only (via `configwire ^0.3.0`:
  `Targeting.toQueryParameters` emits `?userHash=<sha256Hex16(userId)>`).
  Raw `uid` is never sent: no `?uid=` emission and no dual-send (hash-only
  by design). **Migration:** no client code change needed unless you depended
  on `?uid=` server-side — key rules off `UserHash` instead. Supported
  server: `configwire ^0.1.9` or later (dual-accept window):
  **upgrade the server first**; older servers (`<0.1.9`) will treat
  these fetches as anonymous. Floor bumped to `configwire: ^0.3.0`.

## 0.1.2

* Example app (`example/`): flag-gated UI driving real widgets from
  `welcome_message` (String) and `new_checkout` (Bool) flags with
  in-app defaults, `connectRealtime` / `onUpdate` live rebuild without
  manual fetch, `trackExposure` at the flag-driven branches, plus a
  debug panel (fetch status, version, etag, targeting) and an
  admin-themed shell (`config_wire_screen`, `init_gate`, `cw_theme`,
  `widgets`). Platform shells for android, ios, linux, macos, windows,
  and web so `flutter run` works on every target. No library changes.

## 0.1.1

* WASM compatibility: read the app version via
  `package_info_plus_platform_interface` instead of
  `package:package_info_plus/package_info_plus.dart` (which unconditionally
  exports its `dart:io` Linux implementation and cost 10 pub.dev platform
  points). Runtime behavior is unchanged — the `package_info_plus` plugin
  still provides the platform implementations.
* Factory hardening (`ConfigWireFlutter.createConfigWire` never throws):
  a throwing `idGenerator` degrades to anonymous (pins nothing instead of
  propagating); `collectDevice: false` defensive-copies `customAttrs` to
  match the `true` path; device targeting trims `appVersion` before the
  `+build` strip.

## 0.1.0

* `SharedPreferencesCacheStore`: `SharedPreferencesAsync`-backed `CacheStore` with per-env key; blocked storage degrades to load-null/save-noop and never throws.
* Device targeting collector: platform, build-stripped appVersion, locale/country; customAttrs from explicit input.
* Stable install ID: a 15-char lowercase `[a-z0-9]` ID (default `defaultIdGenerator`) is persisted and sent as `?userHash=` (sha256Hex16 of the ID) with each fetch. Pass `idGenerator` to supply the first-run value from your own source; it runs at most once per install. `customAttrs` rides alongside the install ID and is never persisted.
* Prefs keys share the `<prefixCache>.<env>.<suffix>` scheme (`cache` for values, `userId` for the install ID; `prefixCache` defaults to `'configwire'`).
* `ConfigWireFlutter.createConfigWire` one-call factory returning a wired `ConfigWire`.
