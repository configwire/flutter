// ignore_for_file: prefer_initializing_formals
// (decorator ctor params `inner`/`prefs`/`env` keep their public names for
// the call-site API; the backing fields are intentionally private, so no
// initializing formal.)
import 'package:configwire/configwire.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_targeting.dart';
import 'prefs_store.dart';

/// Factory namespace for building a fully-wired [ConfigWire] on Flutter.
///
/// One call supplies the two Flutter-specific pieces the pure-Dart client
/// cannot provide on its own: a [SharedPreferencesAsync]-backed [CacheStore]
/// and device-derived [Targeting]. The returned [ConfigWire] is a plain
/// instance — construct-then-[ConfigWire.setTargeting], never a subclass —
/// so every `client/dart` API behaves exactly as documented there.
///
/// Two shapes are supported:
///
/// * Bring-your-own [ConfigWire] (preferred): construct it in caller code,
///   then `await cw.configureFlutter(...)` resolves the install ID +
///   device targeting, calls `cw.setTargeting`, and optionally runs
///   `cw.ensureInitialized()`.
/// * One-shot: `await ConfigWireFlutter.createConfigWire(...)`
///   (deprecated, use `cw.configureFlutter` instead) builds a prefs-backed
///   [ConfigWire] and runs the same init.
///
/// Identity: targeting is always anonymous — the former stable install-ID
/// surface (custom ID generator, persisted install ID, `?userHash=`
/// emission) has been removed. Bucketing rides the stable `?b=` slot.
/// * First launch and later launches behave identically: no ID is
///   generated, persisted, or read back.
/// * [collectDevice] (default true) fills platform/appVersion/locale/country;
///   false skips device collection entirely.
/// * Only the stable `?b=` bucket is ever persisted — never device fields.
///
/// Like the core `ConfigWire` constructor, configuring never fetches:
/// `ensureInitialized` defaults to `false` (targeting only — hermetic, no
/// network). Pass `true`, or call [ConfigWire.ensureInitialized]
/// afterwards, to load the cache plus force-fetch against [baseUrl].
///
/// Targeting is always anonymous: no install ID is saved to
/// [SharedPreferencesAsync] and nothing identity-like is restored on
/// later launches. Bucketing rides the stable `?b=` slot.
///
/// Prefs keys share the `<prefixCache>.<env>.<suffix>` scheme (`suffix` is
/// `cache` for values, `bucket` for the non-prefs fallback); pass a custom
/// [prefixCache] (deprecated, use `store:` instead) to isolate multiple SDK
/// instances in one app. Prefs-backed stores carry the stable `?b=`
/// bucket in the cache row; non-prefs stores mirror it through the
/// `prefs:`/`prefixCache:` fallback so the bucket still survives restarts.
abstract final class ConfigWireFlutter {
  /// Per-instance flutter-targeting state. [ConfigWire] lives in the
  /// pure-Dart package and cannot carry Flutter init flags, so the guard
  /// lives here. Targeting resolves once per [ConfigWire] instance
  /// (first-call-wins; later calls join the in-flight future or no-op).
  /// The final fetch step is NOT guarded here — it delegates to
  /// [ConfigWire.ensureInitialized], which is itself idempotent.
  static final Expando<Future<void>> _flutterTargetingInFlight =
      Expando<Future<void>>('configwire_flutter_targeting_in_flight');
  static final Expando<bool> _flutterTargetingDone = Expando<bool>(
    'configwire_flutter_targeting_done',
  );

  /// Resolves Flutter-side targeting for [cw], then optionally runs
  /// [ConfigWire.ensureInitialized].
  ///
  /// Safe to call multiple times per [cw]: targeting resolves once
  /// (first-call-wins; concurrent callers join the same in-flight future
  /// and later callers no-op with their params ignored). The fetch step
  /// delegates to [ConfigWire.ensureInitialized] every time, which
  /// dedupes itself — so a first call with `ensureInitialized: false`
  /// (targeting only) followed by a call with `true` still fetches.
  ///
  /// Never throws: bucket-fallback I/O swallows errors, device collection
  /// degrades (per-field for the default collector, identity-only for a
  /// throwing custom collector), and [ConfigWire.ensureInitialized] never
  /// throws.
  static Future<void> _configureFlutter(
    ConfigWire cw, {
    Map<String, Object?>? customAttrs,
    bool collectDevice = true,
    @Deprecated('Use store: with SharedPreferencesCacheStore instead')
    String prefixCache = 'configwire',
    bool ensureInitialized = false,
    @Deprecated('Use store: with SharedPreferencesCacheStore instead')
    SharedPreferencesAsync? prefs,
    DeviceTargetingCollector? collector,
    CacheStore? store,
  }) async {
    if (_flutterTargetingDone[cw] == true) {
      if (ensureInitialized) await cw.ensureInitialized();
      return;
    }
    final inFlight = _flutterTargetingInFlight[cw];
    if (inFlight != null) {
      await inFlight;
      if (ensureInitialized) await cw.ensureInitialized();
      return;
    }
    final future = _resolveFlutterTargeting(
      cw,
      customAttrs: customAttrs,
      collectDevice: collectDevice,
      prefixCache: prefixCache,
      prefs: prefs,
      collector: collector,
      store: store,
    );
    _flutterTargetingInFlight[cw] = future;
    try {
      await future;
      _flutterTargetingDone[cw] = true;
    } finally {
      _flutterTargetingInFlight[cw] = null;
    }
    if (ensureInitialized) await cw.ensureInitialized();
  }

  static Future<void> _resolveFlutterTargeting(
    ConfigWire cw, {
    required Map<String, Object?>? customAttrs,
    required bool collectDevice,
    required String prefixCache,
    required SharedPreferencesAsync? prefs,
    required DeviceTargetingCollector? collector,
    required CacheStore? store,
  }) async {
    // Apply store before any cache load; late calls are ignored by setStore.
    // Explicit `store:` param wins; otherwise attach the default prefs
    // store (namespaced by cw.env, honoring legacy prefs/prefixCache) only
    // when no explicit store exists — single source of truth, no env
    // duplication, no dual-backend split.
    if (store != null) {
      cw.setStore(store);
    } else if (!cw.hasExplicitStore) {
      cw.setStore(
        SharedPreferencesCacheStore(
          prefs: prefs,
          env: cw.env,
          prefixCache: prefixCache,
        ),
      );
    }
    // Stable-bucket fallback for non-prefs backing stores: a prefs-backed
    // store already carries `CacheData.bucket` in its namespaced cache row,
    // but session-only stores (e.g. `MemoryCacheStore`) have no row
    // lifecycle, so the bucket would be dropped on every restart. Wrap such
    // stores so the bucket mirrors through prefs under
    // `'<prefixCache>.<env>.bucket'` and is
    // merged back into bucket-less rows. An explicit legacy `prefs:` or
    // non-default `prefixCache:` wins for the fallback key.
    // The wrapper never invents a bucket: it only preserves the T5-managed
    // `CacheData.bucket` (server-minted, `200`-only) so the fetch wire can
    // send `?b=` on the next cold start.
    final attached = cw.store;
    if (attached is! SharedPreferencesCacheStore) {
      cw.setStore(
        _BucketFallbackCacheStore(
          inner: attached,
          prefs: prefs ?? SharedPreferencesAsync(),
          env: cw.env,
          prefixCache: prefixCache,
        ),
      );
    }
    // No install-ID surface remains: targeting resolves anonymously and
    // bucketing rides the stable `?b=` slot.
    Targeting targeting;
    if (collectDevice) {
      // A custom collector may throw; degrade to customAttrs-only rather
      // than breaking the never-throws contract (the default collector
      // already degrades per-field internally and never throws itself).
      try {
        targeting = await (collector ?? DeviceTargetingCollector())
            .resolveDeviceTargeting(customAttrs ?? {});
      } catch (_) {
        targeting = Targeting(
          customAttrs: Map<String, Object?>.of(customAttrs ?? {}),
        );
      }
    } else {
      targeting = Targeting(
        customAttrs: Map<String, Object?>.of(customAttrs ?? {}),
      );
    }
    cw.setTargeting(targeting);
  }

  /// Deprecated: construct your own [ConfigWire] and call
  /// `await cw.configureFlutter(...)` instead.
  ///
  /// Note the default flip: `createConfigWire` fetches unless
  /// `ensureInitialized: false`, while `configureFlutter` only targets
  /// unless `ensureInitialized: true` — to preserve this method's
  /// behavior, fetch explicitly:
  /// ```dart
  /// final cw = ConfigWire(
  ///   apiKey: apiKey, env: env, baseUrl: baseUrl, defaults: defaults,
  ///   store: SharedPreferencesCacheStore(
  ///     env: env, prefixCache: prefixCache,
  ///   ),
  /// );
  /// await cw.configureFlutter(customAttrs: customAttrs);
  /// await cw.ensureInitialized();
  /// ```
  @Deprecated('Use your own ConfigWire + cw.configureFlutter() instead')
  static Future<ConfigWire> createConfigWire({
    required String apiKey,
    required String env,
    required String baseUrl,
    Map<String, Object?> defaults = const {},
    Map<String, Object?>? customAttrs,
    bool collectDevice = true,
    String prefixCache = 'configwire',
    Duration? minimumFetchInterval,
    Duration? fetchTimeout,
    bool verbose = false,
    bool ensureInitialized = true,
  }) async {
    final prefs = SharedPreferencesAsync();
    final cw = ConfigWire(
      apiKey: apiKey,
      env: env,
      baseUrl: baseUrl,
      defaults: defaults,
      store: SharedPreferencesCacheStore(
        prefs: prefs,
        env: env,
        prefixCache: prefixCache,
      ),
      minimumFetchInterval: minimumFetchInterval ?? const Duration(hours: 12),
      fetchTimeout: fetchTimeout ?? const Duration(seconds: 60),
      verbose: verbose,
    );
    await _configureFlutter(
      cw,
      customAttrs: customAttrs,
      collectDevice: collectDevice,
      prefixCache: prefixCache,
      ensureInitialized: ensureInitialized,
      prefs: prefs,
    );
    return cw;
  }

  /// Clears the stable bucket on logout/user-switch without touching
  /// values, etag, version, or targeting — the Flutter dual-key mirror of
  /// Dart's [ConfigWire.clearBucket] (same name, Flutter namespaced).
  ///
  /// Runs Dart's clear (nulls the in-memory bucket and re-persists the
  /// current row with `bucket: null`, so the next fetch sends no `?b=`;
  /// for non-prefs stores the attached fallback decorator already drops
  /// its key through its null path), then removes the prefs fallback key
  /// via [clearPersistedBucket] on both the store-owned backend (when
  /// prefs-backed) and the resolved legacy backend, so a stray fallback
  /// from an earlier configuration can never resurrect. Row-wins
  /// precedence and reinstall-wipes-row semantics are untouched; clearing
  /// one env never touches another. Never throws: blocked storage
  /// degrades to a memory-only clear. Pass the same `prefs:` /
  /// `prefixCache:` used at configure time when a legacy override was
  /// used for the fallback key.
  static Future<void> clearBucket(
    ConfigWire cw, {
    SharedPreferencesAsync? prefs,
    String prefixCache = 'configwire',
  }) async {
    await cw.clearBucket();
    final attached = cw.store;
    if (attached is SharedPreferencesCacheStore) {
      await clearPersistedBucket(
        prefs: attached.prefs,
        env: attached.env,
        prefixCache: attached.prefixCache,
      );
    }
    final fallbackPrefs =
        prefs ??
        (attached is SharedPreferencesCacheStore
            ? attached.prefs
            : SharedPreferencesAsync());
    await clearPersistedBucket(
      prefs: fallbackPrefs,
      env: cw.env,
      prefixCache: prefixCache,
    );
  }
}

/// Flutter entry point on your own [ConfigWire]:
/// `await cw.configureFlutter(...)` resolves device
/// targeting, calls `cw.setTargeting`, and optionally runs
/// [ConfigWire.ensureInitialized].
///
/// Targeting is always anonymous: the former install-ID surface has been
/// removed and nothing identity-like is emitted; bucketing rides the
/// stable `?b=` slot. See [ConfigWireFlutter] for the store contract.
extension ConfigWireFlutterExtension on ConfigWire {
  /// One-shot Flutter init for this [ConfigWire].
  ///
  /// A [ConfigWire] built without an explicit store gets a default
  /// [SharedPreferencesCacheStore] namespaced by `cw.env` (single source
  /// of truth, no env duplication; legacy `prefs:`/`prefixCache:` are
  /// honored for the auto-attached store). Precedence is explicit `store:`
  /// param > explicit ctor store > auto-default. Applied via
  /// [ConfigWire.setStore] before any cache load. Late calls are ignored.
  ///
  /// Safe to call multiple times: targeting resolves once (first-call-wins;
  /// concurrent callers join the same in-flight future and later callers
  /// no-op with their params ignored). Like the core constructor,
  /// configuring never fetches by default (`ensureInitialized: false`);
  /// pass `true` or call [ConfigWire.ensureInitialized] afterwards for
  /// the cache load plus forced fetch.
  ///
  /// Never throws: device collection degrades per-field for the default
  /// collector (customAttrs-only for a throwing custom collector), and
  /// [ConfigWire.ensureInitialized] never throws.
  Future<void> configureFlutter({
    Map<String, Object?>? customAttrs,
    bool collectDevice = true,
    @Deprecated('Use store: with SharedPreferencesCacheStore instead')
    String prefixCache = 'configwire',
    bool ensureInitialized = false,
    @Deprecated('Use store: with SharedPreferencesCacheStore instead')
    SharedPreferencesAsync? prefs,
    DeviceTargetingCollector? collector,
    CacheStore? store,
  }) => ConfigWireFlutter._configureFlutter(
    this,
    customAttrs: customAttrs,
    collectDevice: collectDevice,
    prefixCache: prefixCache,
    ensureInitialized: ensureInitialized,
    prefs: prefs,
    collector: collector,
    store: store,
  );
}

/// Prefs key for the stable-bucket fallback:
/// `'<prefixCache>.<Uri.encodeComponent(env)>.bucket'`
/// (default prefix `'configwire'`, e.g. `'configwire.dev.bucket'`).
///
/// Same `<prefixCache>.<env>` namespacing as the cache row; only the suffix
/// differs (`bucket` vs the cache row's `cache`). Used solely for
/// non-prefs backing stores, whose cache rows are session-only — prefs
/// backed stores carry the bucket in the row itself and never touch this
/// key, so the two sources can never fork.
String _bucketKeyFor({
  required String env,
  String prefixCache = 'configwire',
}) => '$prefixCache.${Uri.encodeComponent(env)}.bucket';

/// Canonical bucket validation: plain `0`-`9999` ints only.
/// Wrong shapes and out-of-range values parse as absent (null), mirroring
/// the tolerant `CacheData.bucket` rule (never coerced, never throws).
bool _isCanonicalBucket(Object? raw) => raw is int && raw >= 0 && raw <= 9999;

/// Loads the fallback bucket, or null on miss/invalid/error.
///
/// A stored value parses only when it is a plain `0`-`9999` int string
/// (`"007"`, whitespace-padded, floats, and out-of-range values count as
/// absent). Blocked storage degrades to load-absent: never throws.
Future<int?> _loadPersistedBucket({
  required SharedPreferencesAsync prefs,
  required String env,
  String prefixCache = 'configwire',
}) async {
  try {
    final raw = await prefs.getString(
      _bucketKeyFor(env: env, prefixCache: prefixCache),
    );
    if (raw == null) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null || !_isCanonicalBucket(parsed)) return null;
    // `int.tryParse` accepts a leading `+` (`"+42"`) and surrounding
    // whitespace; the canonical form is the plain round-trip, so anything
    // else counts as absent (mirrors the strict `?b=` server rule).
    if (parsed.toString() != raw) return null;
    return parsed;
  } catch (_) {
    return null;
  }
}

/// Persists the fallback bucket. Swallows ALL errors so callers never
/// observe a throw. A null (or non-canonical) bucket clears the key
/// instead, so stale fallbacks can never resurrect past their row.
Future<void> _savePersistedBucket({
  required SharedPreferencesAsync prefs,
  required String env,
  required int? bucket,
  String prefixCache = 'configwire',
}) async {
  try {
    final key = _bucketKeyFor(env: env, prefixCache: prefixCache);
    if (bucket != null && _isCanonicalBucket(bucket)) {
      await prefs.setString(key, bucket.toString());
    } else {
      await prefs.remove(key);
    }
  } catch (_) {
    // Swallow: blocked storage degrades to save-noop by design.
  }
}

/// Removes the persisted fallback bucket. Swallows ALL errors so callers
/// never observe a throw (same never-throws bucket discipline as above).
Future<void> clearPersistedBucket({
  required SharedPreferencesAsync prefs,
  required String env,
  String prefixCache = 'configwire',
}) async {
  try {
    await prefs.remove(_bucketKeyFor(env: env, prefixCache: prefixCache));
  } catch (_) {
    // Swallow: blocked storage degrades to clear-noop by design.
  }
}

/// [CacheStore] decorator preserving the stable bucket for non-prefs
/// backing stores (session-only rows).
///
/// * `load()` delegates to the inner store, then fills a missing bucket
///   from the prefs fallback (row bucket always wins when present). When
///   the inner store is cold (null) but a fallback bucket exists, a
///   minimal row carrying just the bucket is synthesized: empty etag (so
///   no `If-None-Match` is sent), version 0, and empty values over the
///   in-app defaults — behaviorally identical to a cold cache except the
///   fetch wire can send `?b=`.
/// * `save()` delegates verbatim (inner error semantics preserved), then
///   best-effort mirrors `data.bucket` to the fallback key (clearing it
///   when the saved row is bucket-less).
///
/// Never throws itself: fallback I/O swallows all errors, and inner
/// `load()` errors propagate exactly as the undecorated store would
/// produce them (the client's init treats a throwing load as a cold
/// cache). Reinstall wipes prefs with everything else, so a reinstalled
/// app loads bucket-absent and the next cold `200` mints a new bucket.
class _BucketFallbackCacheStore implements CacheStore {
  _BucketFallbackCacheStore({
    required CacheStore inner,
    required SharedPreferencesAsync prefs,
    required String env,
    String prefixCache = 'configwire',
  }) : _inner = inner,
       _prefs = prefs,
       _env = env,
       _prefixCache = prefixCache;

  final CacheStore _inner;
  final SharedPreferencesAsync _prefs;
  final String _env;
  final String _prefixCache;

  @override
  Future<CacheData?> load() async {
    final row = await _inner.load();
    final fallback = await _loadPersistedBucket(
      prefs: _prefs,
      env: _env,
      prefixCache: _prefixCache,
    );
    if (fallback == null) return row;
    if (row == null) {
      return CacheData(
        etag: '',
        version: 0,
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        values: const {},
        bucket: fallback,
      );
    }
    if (row.bucket != null) return row;
    return CacheData(
      etag: row.etag,
      version: row.version,
      fetchedAt: row.fetchedAt,
      values: Map<String, Object?>.from(row.values),
      variants: Map<String, String>.from(row.variants),
      bucket: fallback,
    );
  }

  @override
  Future<void> save(CacheData data) async {
    await _inner.save(data);
    await _savePersistedBucket(
      prefs: _prefs,
      env: _env,
      bucket: data.bucket,
      prefixCache: _prefixCache,
    );
  }
}
