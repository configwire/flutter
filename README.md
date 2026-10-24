# configwire_flutter

Flutter companion to the pure-Dart [configwire](https://github.com/configwire/dart) client
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
  configwire_flutter: ^0.2.3
```

Then `flutter pub get`.

## Usage

The snippet below matches `example/main.dart`. Copy, paste, run.
With no server running, the startup fetch fails gracefully and the demo
serves defaults. Point `baseUrl` at a real server to load the cache
plus force-fetch on startup.

```dart
import 'package:configwire_flutter/configwire_flutter.dart';

/// Offline-first demo: with no server running, the startup fetch fails
/// gracefully and the demo serves defaults. Point `baseUrl` at a real
/// server to load the cache plus force-fetch on startup.
Future<void> main() async {
  final cw = ConfigWire(
    apiKey: 'YOUR_SDK_KEY', // sent as X-ConfigWire-Key, never printed
    env: 'dev',
    baseUrl: 'http://127.0.0.1:8090',
    defaults: {'launch_flag': false},
  );
  await cw.configureFlutter(
    customAttrs: {'plan': 'pro'},
  );
  await cw.ensureInitialized();

  assert(cw.getBool('launch_flag') == false);
  // NOTE: values printed, apiKey never printed.
  // ignore: avoid_print
  print(
    'launch_flag=${cw.getBool('launch_flag')} targeting=${cw.targeting}',
  );
  await cw.dispose();
}
```

> `cw.configureFlutter` wires Flutter-side targeting onto your own
> `configwire` `ConfigWire`. Read more
> in the [`configwire`](https://pub.dev/packages/configwire) package:
> reading values, variants, fetch lifecycle, targeting, stable `?b=`
> bucket, realtime, analytics, logging, and cache.

## Targeting

Targeting attributes are sent as fetch query params so the server can
evaluate `rules` per fetch. Collection is automatic
(`package_info_plus`; locale needs no extra dependency).
Targeting stays sticky through
`cw.setTargeting` / `cw.updateTargeting` exactly as in `configwire`.

Default targeting (every fetch carries these unless empty, in which case
the param is omitted):

| Field         | Query param              | Default value                                                                                                                   | Source                  |
| ------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `userId`      | `?userHash=` (deprecated, compat-only) | Stable install ID: a 15-char lowercase `[a-z0-9]` ID, generated once and persisted, emitted as `?userHash=<sha256hex16>` at fetch time. Customize the first-run value only via `idGenerator` (default `defaultIdGenerator`, built on `generateUserId`). Deprecated: the server ignores `userHash` for bucketing/exposure identity (accepted-but-ignored, `X-CW-Deprecated-userHash`); bucketing rides the stable `?b=` slot below | Persistence via the restored `user_store` helpers on the store-owned backend |
| `platform`    | `?platform=`             | `android` \| `ios` \| `macos` \| `windows` \| `linux` \| `fuchsia` \| `web` (`kIsWeb` forces `web`)                             | `defaultTargetPlatform` |
| `appVersion`  | `?appVersion=`           | Package version with `+build` metadata stripped for strict-semver compare (e.g. `1.0.0+1` → `1.0.0`); empty (omitted) when unreadable | `package_info_plus`     |
| `locale`      | `?locale=`               | `toLanguageTag` (e.g. `en-US`); empty (omitted) when unreadable                                                               | `PlatformDispatcher.locale` |
| `country`     | `?country=` (deprecated, ignored) | `countryCode` (e.g. `US`); empty (omitted) when absent or unreadable. Deprecated: the server derives country from request headers and ignores the client-sent value | `PlatformDispatcher.locale` |
| `customAttrs` | `?attrs=` (compact JSON) | `{}` (omitted) unless passed via `cw.configureFlutter(customAttrs:)`                                                           | Caller input            |

Identity is a random per-install value: only its SHA-256 hash (truncated to
16 hex chars) ever leaves the device, and the server stores no raw identity.
The hash emission stays for the compat window only — the server ignores it
for bucketing and exposure identity, so experiment arms ride the stable
`?b=` bucket instead: each evaluated `200` mints a `bucket` (`0`-`9999`)
that persists first-write-wins and is sent as `?b=` on fetch and events,
surviving the server's daily anonID rotation.
Non-prefs stores keep the 0.2.x stable ID via the prefs fallback (legacy
`prefs:`/`prefixCache:` persistence), so no install goes anonymous while
prefs are writable. The bucket gets the same fallback discipline:
prefs-backed stores carry it in the namespaced cache row, while
session-only stores (e.g. `MemoryCacheStore`) mirror it through prefs
under `<prefix>.<env>.bucket` and merge it back into bucket-less rows —
the wrapper never invents a bucket, only preserves the server-minted one.
On logout/user-switch call `ConfigWireFlutter.clearBucket(cw)` (the
Flutter mirror of `cw.clearBucket()`): it nulls the in-memory bucket,
re-persists the row with `bucket: null`, and removes the prefs fallback
key, so the next fetch sends no `?b=`.

Bare `ConfigWire(...)` plus `configureFlutter()` gets disk persistence
and a stable install ID via an auto-attached
`SharedPreferencesCacheStore(env: cw.env)` honoring legacy
`prefs:`/`prefixCache:`. Store precedence: explicit
`store:` param > explicit ctor store > auto-attached
`SharedPreferencesCacheStore(env: cw.env)`.

## Migrating from 0.2.x

No migration needed — 0.2.x calls compile and behave as before:
`ConfigWireFlutter.createConfigWire(...)` and
`configureFlutter(prefs: ..., prefixCache: ...)` keep working
(deprecated shims), and `<prefix>.<env>.userId` keys are adopted as-is,
so existing installs keep their buckets with no reshuffle. The preferred
shape going forward is bring-your-own (optional):

**1. One-shot factory → bring-your-own (optional):**

```dart
// Still works (deprecated):
final cw = await ConfigWireFlutter.createConfigWire(
  apiKey: apiKey, env: env, baseUrl: baseUrl,
  customAttrs: {'plan': 'pro'},
);

// Preferred:
final cw = ConfigWire(
  apiKey: apiKey, env: env, baseUrl: baseUrl,
  defaults: const {},
);
await cw.configureFlutter(customAttrs: {'plan': 'pro'});
await cw.ensureInitialized();
```

(Note the default flip: `createConfigWire` fetches unless
`ensureInitialized: false`, while `configureFlutter` never fetches —
call `ensureInitialized` explicitly.)

**2. `prefs:` / `prefixCache:` (optional)** — these still work and still
govern the install-ID key verbatim. New code should prefer the store
(`SharedPreferencesCacheStore(env:…, prefixCache:…)`) with the `store:`
param instead; an explicit legacy `prefs:` or non-default `prefixCache:`
continues to win for the ID key.

**3. `user_store` is back** — `loadPersistedUserId`,
`savePersistedUserId`, `clearPersistedUserId`, `userIdKeyFor`,
`defaultIdGenerator`, and `generateUserId` return with the same 0.2.x
names (deprecations lifted). The store exposes its backend via a `prefs`
getter so the helpers can run on the store-owned backend.

## License

MIT — Copyright (c) 2026 Lam Thanh Nhan. See [LICENSE](LICENSE).
