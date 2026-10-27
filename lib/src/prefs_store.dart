// ignore_for_file: prefer_initializing_formals
// (constructor param `prefs` must keep its public name for the test API;
// the backing field is intentionally private, so no initializing formal.)
import 'dart:convert';

import 'package:configwire/configwire.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Derives the prefs-namespace prefix from a full SDK key.
///
/// Mirrors the server's `KeyPrefix` (`configwire/ingest/hash.go`): the
/// first 8 chars, or the whole key when shorter. SDK keys are ASCII
/// (`'cw-'` + 24 base62), so [String.substring] on UTF-16 code units is
/// safe here — do NOT reuse this for non-ASCII input.
String keyPrefixOf(String apiKey) =>
    apiKey.length > 8 ? apiKey.substring(0, 8) : apiKey;

/// Resolves the prefs-namespace segment for a store: the [keyPrefixOf]
/// prefix when [apiKey] is present, else the legacy [env] string verbatim.
///
/// At least one of [apiKey]/[env] is required (a runtime [ArgumentError]
/// when both are absent, so release builds fail the same way as debug).
/// Only the resolved segment ever appears in prefs key names —
/// the full SDK key is never persisted or logged (same non-sensitive
/// status as the server's `key_prefix` log field).
String storeNamespaceFor({String? apiKey, String? env}) {
  if (apiKey == null && env == null) {
    throw ArgumentError(
      'SharedPreferencesCacheStore requires apiKey or env',
      'apiKey',
    );
  }
  if (apiKey != null) return keyPrefixOf(apiKey);
  return env!;
}

/// Prefs cache-row key for either namespace:
/// `'<prefixCache>.<Uri.encodeComponent(namespace)>.cache'`.
String storeCacheKeyFor({
  String? apiKey,
  String? env,
  String prefixCache = 'configwire',
}) =>
    '$prefixCache.${Uri.encodeComponent(storeNamespaceFor(apiKey: apiKey, env: env))}.cache';

/// [CacheStore] backed by [SharedPreferencesAsync].
///
/// Dual namespace: construct with `apiKey:` (namespaced by its
/// [keyPrefixOf] prefix, e.g. `'configwire.cw-01234.cache'`) or with the
/// legacy `env:` (namespaced by the env string verbatim, byte-identical
/// to before, e.g. `'configwire.dev.cache'`). At least one of
/// `apiKey`/`env` is required (a runtime [ArgumentError] when both are
/// absent). When both are given, `apiKey` wins.
/// The `env` field is functional again (not deprecated): old
/// `env:`-constructed code compiles and behaves exactly as before.
///
/// The T5-managed `CacheData.bucket` slot (server-minted stable bucket
/// `0-9999`) persists inside this same JSON row beside the verbatim `etag`
/// — no separate bucket key is used for prefs-backed stores, so the two
/// can never fork. Rows written before the bucket slot existed load with
/// `bucket` absent (tolerant parse, never throws).
///
/// Reinstall semantics: reinstalling (or clearing app storage) wipes this
/// row with everything else, so the next launch loads bucket-absent and
/// the next cold `200` mints a NEW bucket (expected re-roll).
///
/// Manually-constructed stores never migrate between namespaces: pass the
/// same `apiKey` (or the same `env`) and the row is shared; a key with no
/// prior row starts cold. One-time legacy `env` → prefix moves happen
/// only in the `configureFlutter` auto-attach path (which knows both) and
/// in the deprecated `createConfigWire` factory (same move, run
/// explicitly). Otherwise an upgrade across namespaces starts cold
/// (documented).
///
/// Divergence from [CacheStore.save]'s may-throw permission: this store
/// swallows ALL save errors (blocked storage, denied quota, corrupt
/// backend) and completes normally, so callers never observe a throw.
class SharedPreferencesCacheStore implements CacheStore {
  SharedPreferencesCacheStore({
    SharedPreferencesAsync? prefs,
    String? apiKey,
    String? env,
    String prefixCache = 'configwire',
  }) : _prefs = prefs ?? SharedPreferencesAsync(),
       apiKey = apiKey,
       env = env,
       prefixCache = prefixCache,
       namespace = storeNamespaceFor(apiKey: apiKey, env: env),
       _key = storeCacheKeyFor(
         apiKey: apiKey,
         env: env,
         prefixCache: prefixCache,
       );

  final SharedPreferencesAsync _prefs;
  final String _key;

  /// Full SDK key (memory only, never persisted or logged). Null when the
  /// store was constructed with `env:` only.
  final String? apiKey;

  /// Legacy env namespace of [_key] (verbatim). Null when the store was
  /// constructed with `apiKey:` only.
  final String? env;

  /// Namespace segment of [_key]: the [keyPrefixOf] prefix when `apiKey`
  /// is present, else the legacy `env` string verbatim.
  final String namespace;

  /// Key prefix of [_key].
  final String prefixCache;

  /// Exposes the store-owned backend so bucket helpers run on it.
  SharedPreferencesAsync get prefs => _prefs;

  @override
  Future<CacheData?> load() async {
    try {
      final raw = await _prefs.getString(_key);
      if (raw == null) return null;
      return cacheDataFromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(CacheData data) async {
    try {
      await _prefs.setString(_key, jsonEncode(data.toJson()));
    } catch (_) {
      // Swallow: blocked storage degrades to save-noop by design.
    }
  }
}
