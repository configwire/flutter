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
