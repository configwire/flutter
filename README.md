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
  configwire_flutter: ^0.3.0-rc.2
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

> Bucket (`?b=0-9999`) is the sole identity since `configwire server v0.2.0-rc.1`
> (released 2026-10-25, bucket-only). The SDK sends no `?userHash=`
> and no body `userHash`; `Targeting.userId`, the install-ID
> generation/persistence helpers, and the per-env install-ID prefs keys
> are removed (not deprecated).

Targeting attributes are sent as fetch query params so the server can
evaluate `rules` per fetch. Collection is automatic
(`package_info_plus`; locale needs no extra dependency).
Targeting stays sticky through
`cw.setTargeting` / `cw.updateTargeting` exactly as in `configwire`.

Default targeting (every fetch carries these unless empty, in which case
the param is omitted):

| Field         | Query param              | Default value                                                                                                                   | Source                  |
| ------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------- | ----------------------- |
| `platform`    | `?platform=`             | `android` \| `ios` \| `macos` \| `windows` \| `linux` \| `fuchsia` \| `web` (`kIsWeb` forces `web`)                             | `defaultTargetPlatform` |
| `appVersion`  | `?appVersion=`           | Package version with `+build` metadata stripped for strict-semver compare (e.g. `1.0.0+1` → `1.0.0`); empty (omitted) when unreadable | `package_info_plus`     |
| `locale`      | `?locale=`               | `toLanguageTag` (e.g. `en-US`); empty (omitted) when unreadable                                                               | `PlatformDispatcher.locale` |
| `country`     | `?country=` (deprecated, ignored) | `countryCode` (e.g. `US`); empty (omitted) when absent or unreadable. Deprecated: the server derives country from request headers and ignores the client-sent value | `PlatformDispatcher.locale` |
| `customAttrs` | `?attrs=` (compact JSON) | `{}` (omitted) unless passed via `cw.configureFlutter(customAttrs:)`                                                           | Caller input            |

Removed: there is no `userId` targeting field and no install-ID
generation or persistence. The install-ID helpers and the
`<prefix>.<env>.userId` prefs key scheme are removed (not deprecated),
so no install ID is generated, stored, or sent.

Identity is the stable `?b=` bucket only: since
`configwire server v0.2.0-rc.1` (released 2026-10-25, bucket-only) nothing
is emitted as identity except `?b=`. Experiment arms ride the
stable `?b=` bucket: each evaluated `200` mints a `bucket` (`0`-`9999`)
that persists first-write-wins and is sent as `?b=` on fetch and events,
surviving the server's daily anonID rotation. The server ignores
identity inputs without rejecting them (event-body `userId` in any
casing is ignored, never stored or logged) and never rejects an empty
or missing `?b=`.
The bucket gets prefs-fallback discipline:
prefs-backed stores carry it in the namespaced cache row, while
session-only stores (e.g. `MemoryCacheStore`) mirror it through prefs
under `<prefix>.<namespace>.bucket` (`namespace` is the first 8 chars of
the SDK key when `apiKey:` is given, else the legacy `env` string
verbatim) and merge it back into bucket-less rows —
the wrapper never invents a bucket, only preserves the server-minted one.
On logout/user-switch call `ConfigWireFlutter.clearBucket(cw)` (the
Flutter mirror of `cw.clearBucket()`): it nulls the in-memory bucket,
re-persists the row with `bucket: null`, and removes the prefs fallback
key, so the next fetch sends no `?b=`.

Rows are dual-namespaced: the cache row is `<prefix>.<namespace>.cache`
(e.g. `configwire.cw-01234.cache` for `apiKey:`, `configwire.dev.cache`
for legacy `env:`) and the non-prefs fallback is
`<prefix>.<namespace>.bucket`. With `apiKey:` only the 8-char prefix
(`namespace` = first 8 chars of the SDK key, e.g. `cw-Ab12Cd`) appears
in prefs key names — the full SDK key is never persisted or logged.
Old `env:`-constructed code compiles and behaves exactly as before
(byte-identical keys); `apiKey:` is opt-in. Key rotation and buckets:
a new key with a NEW 8-char prefix gets its own row, so the next `200`
mints a fresh `?b=` bucket (cold start, cohort reshuffles by design);
distinct keys that happen to share the same first-8 prefix share one
row and reuse the old bucket (no reshuffle). To force a clean cohort
mint until the prefix differs; to keep the cohort stable keep the
prefix. See `ROTATION.md` client notes.

Bare `ConfigWire(...)` plus `configureFlutter()` gets disk persistence
via an auto-attached
`SharedPreferencesCacheStore(apiKey: cw.apiKey, env: cw.env)` honoring legacy
`prefs:`/`prefixCache:`. Store precedence: explicit
`store:` param > explicit ctor store > auto-attached
`SharedPreferencesCacheStore(apiKey: cw.apiKey, env: cw.env)`. Identity is the stable
`?b=` bucket, not an install ID. Upgrading installs keep their buckets: the
`configureFlutter` auto-attach path and the deprecated `createConfigWire`
factory perform a one-time move of legacy
`<prefix>.<env>.cache`/`.bucket` rows to the prefix-namespaced keys
(manually-constructed stores never migrate — same key shares the row,
a key with no prior row starts cold, and a cross-namespace upgrade
without both known starts cold).

## Migrating from 0.2.x

No migration needed — 0.2.x calls compile and behave as before:
`ConfigWireFlutter.createConfigWire(...)` and
`configureFlutter(prefs: ..., prefixCache: ...)` keep working
(deprecated shims), so existing installs keep their buckets with no
reshuffle. The preferred
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
  apiKey: apiKey, baseUrl: baseUrl,
  defaults: const {},
);
await cw.configureFlutter(customAttrs: {'plan': 'pro'});
await cw.ensureInitialized();
```

(Note the default flip: `createConfigWire` fetches unless
`ensureInitialized: false`, while `configureFlutter` never fetches —
call `ensureInitialized` explicitly.)

**2. `prefs:` / `prefixCache:` (optional)** — these still work and still
govern the namespaced cache/bucket keys verbatim. New code should prefer the store
(`SharedPreferencesCacheStore(apiKey:…, prefixCache:…)` or legacy
`SharedPreferencesCacheStore(env:…, prefixCache:…)`) with the `store:`
param instead; an explicit legacy `prefs:` or non-default `prefixCache:`
continues to win for those keys.

**3. Install-ID removal (breaking)** — the install-ID targeting field,
its generation/persistence helpers, and the per-env install-ID prefs
keys are removed (not deprecated). Drop any custom install-ID wiring
and rely on the stable `?b=` bucket; `?b=` bucket persistence is
unchanged.

## License

MIT — Copyright (c) 2026 Lam Thanh Nhan. See [LICENSE](LICENSE).
