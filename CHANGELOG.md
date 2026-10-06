## 0.1.1

* WASM compatibility: read the app version via
  `package_info_plus_platform_interface` instead of
  `package:package_info_plus/package_info_plus.dart` (which unconditionally
  exports its `dart:io` Linux implementation and cost 10 pub.dev platform
  points). Runtime behavior is unchanged — the `package_info_plus` plugin
  still provides the platform implementations.

## 0.1.0

* `SharedPreferencesCacheStore`: `SharedPreferencesAsync`-backed `CacheStore` with per-env key; blocked storage degrades to load-null/save-noop and never throws.
* Device targeting collector: platform, build-stripped appVersion, locale/country; customAttrs from explicit input.
* Stable install ID: a 15-char lowercase `[a-z0-9]` ID (default `defaultIdGenerator`) is persisted and sent as `?uid=` with each fetch. Pass `idGenerator` to supply the first-run value from your own source; it runs at most once per install. `customAttrs` rides alongside the install ID and is never persisted.
* Prefs keys share the `<prefixCache>.<env>.<suffix>` scheme (`cache` for values, `userId` for the install ID; `prefixCache` defaults to `'configwire'`).
* `ConfigWireFlutter.createConfigWire` one-call factory returning a wired `ConfigWire`.
