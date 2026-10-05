# configwire_flutter

Flutter companion to the pure-Dart [configwire](https://github.com/configwire/configwire) client
(fetch, cache, typed getters, realtime).
One call supplies the two Flutter-specific pieces the pure-Dart client
cannot provide on its own: a `SharedPreferencesAsync`-backed `CacheStore`
and device-derived `Targeting`. Everything else behaves exactly as
documented in the `configwire` package.

Server wire details live in the server repo:
`https://github.com/configwire/configwire/blob/main/docs/CONTRACT.md`.

## Install

Once published:

```bash
flutter pub add configwire_flutter
```

Path-dev reality (publish is still pending): depend on it by path, and
keep the checkout layout intact, because this package itself wires
`configwire` via `path: ../dart`:

```yaml
dependencies:
  configwire_flutter:
    path: ../configwire/client/flutter
```

Then `flutter pub get`.

## Usage

The snippet below matches `example/main.dart`. Copy, paste, run.
It stays offline (`ensureInitialized: false`), so it needs no server.
On a real device drop that line (default `true`) to load the cache
plus force-fetch on startup.

```dart
import 'package:configwire_flutter/configwire_flutter.dart';

/// Offline-first demo: `ensureInitialized: false` means no network, so this
/// runs in CI with no server. On a real device drop that line (default true)
/// to load the cache plus force-fetch on startup.
Future<void> main() async {
  final cw = await ConfigWireFlutter.createConfigWire(
    apiKey: 'YOUR_SDK_KEY', // sent as X-ConfigWire-Key, never printed
    env: 'dev',
    baseUrl: 'http://127.0.0.1:8090',
    defaults: {'launch_flag': false},
    userId: 'user-7',
    customAttrs: {'plan': 'pro'},
    ensureInitialized: false,
  );

  assert(cw.getBool('launch_flag') == false);
  // NOTE: values printed, apiKey never printed.
  // ignore: avoid_print
  print(
    'launch_flag=${cw.getBool('launch_flag')} targeting=${cw.targeting}',
  );
  await cw.dispose();
}
```

## Reading values

One import covers everything: `package:configwire_flutter/configwire_flutter.dart`
re-exports `package:configwire/configwire.dart`, so every getter, fetch,
and realtime API from the pure-Dart client is available with no second
import. All reads are synchronous over the in-memory view
(`{...defaults, ...serverValues}`). Every getter returns a nullable
type and takes a nullable fallback (default null) used on missing
keys or type mismatches: `cw.getBool('launch_flag')` is `bool?`, null
when missing or mistyped; `cw.getString('welcome', fallback: 'hi')`
subs `'hi'` on a miss. See the `configwire` README for the full
getter, variant, fetch-lifecycle, realtime, and logging reference.

## Targeting

Targeting attributes are sent as fetch query params so the server can
evaluate `rules` per fetch. Device collection is automatic
(`package_info_plus`; locale needs no extra
dependency): platform from `defaultTargetPlatform` (`kIsWeb` forces
`web`), `appVersion` with `+build` metadata stripped for strict-semver
compare, locale via `toLanguageTag` with country from `countryCode`.
`customAttrs` comes from the caller's explicit input.
Targeting stays sticky through
`cw.setTargeting` / `cw.updateTargeting` exactly as in `configwire`.

Override precedence in `createConfigWire`:

| # | Condition | Result |
|---|-----------|--------|
| 1 | `explicitTargeting` is given | Used as-is; device collection is skipped entirely |
| 2 | `collectDevice: true` (default), no explicit targeting | `userId` / `customAttrs` merge over the auto-collected device targeting: explicit non-empty scalars win per field, `customAttrs` comes from the explicit input |
| 3 | `collectDevice: false`, no explicit targeting | Anonymous except for `userId` / `customAttrs` |

## Cache

Persistence is a `SharedPreferencesAsync`-backed `CacheStore`, wired
automatically by `createConfigWire`. Prefs key:
`cacheKey ?? 'configwire.cache.<Uri.encodeComponent(env)>'`.
Blocked storage degrades to load-null/save-noop: the client keeps
serving defaults plus server fetches and never throws. Saves swallow
all errors by design, so callers never observe a throw.

Values persist as cleartext JSON: never put tokens, secrets, or PII
into flag values or defaults (on Web the store is additionally readable
by site JS, so the XSS framing applies). Blocked storage (private
mode, denied quota) degrades to load-null/save-noop — the client keeps
serving defaults plus server fetches and never throws.

See `example/main.dart` for a runnable demo.

## License

MIT — Copyright (c) 2026 Lam Thanh Nhan. See [LICENSE](LICENSE).
