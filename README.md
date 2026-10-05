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

Or pin it in your `pubspec.yaml`:

```yaml
dependencies:
  configwire_flutter: ^0.1.0
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
evaluate `rules` per fetch. Collection is automatic
(`package_info_plus`; locale needs no extra dependency).
Targeting stays sticky through
`cw.setTargeting` / `cw.updateTargeting` exactly as in `configwire`.

Default targeting (every fetch carries these unless empty, in which case
the param is omitted):

| Field         | Query param              | Default value                                                                                                                                                                                                  | Source                                     |
| ------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| `userId`      | `?uid=`                  | Stable install ID: a 15-char lowercase `[a-z0-9]` ID, generated once and persisted. Customize the first-run value only via `idGenerator` (default `defaultIdGenerator`); `''` stays anonymous and pins nothing | `SharedPreferencesAsync` (+ `idGenerator`) |
| `platform`    | `?platform=`             | `android` \| `ios` \| `macos` \| `windows` \| `linux` \| `fuchsia` \| `web` (`kIsWeb` forces `web`)                                                                                                            | `defaultTargetPlatform`                    |
| `appVersion`  | `?appVersion=`           | Package version with `+build` metadata stripped for strict-semver compare (e.g. `1.0.0+1` → `1.0.0`); empty (omitted) when unreadable                                                                          | `package_info_plus`                        |
| `locale`      | `?locale=`               | `toLanguageTag` (e.g. `en-US`); empty (omitted) when unreadable                                                                                                                                                | `PlatformDispatcher.locale`                |
| `country`     | `?country=`              | `countryCode` (e.g. `US`); empty (omitted) when absent or unreadable                                                                                                                                           | `PlatformDispatcher.locale`                |
| `customAttrs` | `?attrs=` (compact JSON) | `{}` (omitted) unless passed via `createConfigWire(customAttrs:)`                                                                                                                                              | Caller input                               |

Identity in `createConfigWire`:

| #   | Layer                                              | Result                                                                                                                                                                                                 |
| --- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Install ID                                         | Generated once, persisted, always the `userId`. Customize the first-run value only via `idGenerator` (default `defaultIdGenerator`); later launches reuse the persisted value without calling it again |
| 2   | Device values (`collectDevice: true`, the default) | Fill platform/appVersion/locale/country around the install ID                                                                                                                                          |
| +   | `collectDevice: false`                             | Skips device collection entirely: install ID plus `customAttrs`                                                                                                                                        |
| +   | `customAttrs`                                      | Sent as `?attrs=` JSON alongside the install ID; never persisted                                                                                                                                       |

Prefs keys share the `<prefix>.<env>.<suffix>` scheme 
(`prefixCache`, default `'configwire'`):

| Suffix   | Key                                                                         | Holds              |
| -------- | --------------------------------------------------------------------------- | ------------------ |
| `cache`  | `<prefix>.<Uri.encodeComponent(env)>.cache` (e.g. `configwire.dev.cache`)   | Cached flag values |
| `userId` | `<prefix>.<Uri.encodeComponent(env)>.userId` (e.g. `configwire.dev.userId`) | Stable install ID  |

Only the install ID is persisted — never `customAttrs` or device fields.
The install ID is fully internal: it is generated once, reused on every
launch, and sent as `?uid=` with each fetch. An `idGenerator` returning
`''` stays anonymous for that launch and pins nothing.

```dart
// Custom prefix example:
final cw2 = await ConfigWireFlutter.createConfigWire(
  apiKey: 'YOUR_SDK_KEY',
  env: 'dev',
  baseUrl: 'http://127.0.0.1:8090',
  prefixCache: 'myapp', // keys: myapp.dev.cache / myapp.dev.userId
  ensureInitialized: false,
);
```

## Cache

Persistence is a `SharedPreferencesAsync`-backed `CacheStore`, wired
automatically by `createConfigWire`. Prefs key:
`'<prefixCache>.<Uri.encodeComponent(env)>.cache'`
(e.g. `configwire.dev.cache`; pass `prefixCache: 'myapp'` to isolate to
`myapp.dev.cache` / `myapp.dev.userId`).
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
