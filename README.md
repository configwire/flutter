# configwire_flutter

Flutter companion to the pure-Dart [configwire](https://github.com/configwire/configwire) client
(fetch, cache, typed getters, realtime).
One call supplies the two Flutter-specific pieces the pure-Dart client
cannot provide on its own: a `SharedPreferencesAsync`-backed `CacheStore`
and device-derived `Targeting`. Everything else behaves exactly as
documented in the `configwire` package.

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

> `createConfigWire` returns a plain `configwire` `ConfigWire`. Read more
> in the [`configwire`](https://pub.dev/packages/configwire) package:
> reading values, variants, fetch lifecycle, realtime, analytics,
> logging, and cache.

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

## License

MIT — Copyright (c) 2026 Lam Thanh Nhan. See [LICENSE](LICENSE).
