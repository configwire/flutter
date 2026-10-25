// ignore_for_file: prefer_initializing_formals
// (constructor param `prefs` must keep its public name for the test API;
// the backing field is intentionally private, so no initializing formal.)
import 'dart:convert';

import 'package:configwire/configwire.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [CacheStore] backed by [SharedPreferencesAsync].
///
/// Prefs key: `'<prefixCache>.<Uri.encodeComponent(env)>.cache'`
/// (default prefix `'configwire'`, e.g. `'configwire.dev.cache'`).
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
/// Divergence from [CacheStore.save]'s may-throw permission: this store
/// swallows ALL save errors (blocked storage, denied quota, corrupt
/// backend) and completes normally, so callers never observe a throw.
class SharedPreferencesCacheStore implements CacheStore {
  SharedPreferencesCacheStore({
    SharedPreferencesAsync? prefs,
    required String env,
    String prefixCache = 'configwire',
  }) : _prefs = prefs ?? SharedPreferencesAsync(),
       env = env,
       prefixCache = prefixCache,
       _key = '$prefixCache.${Uri.encodeComponent(env)}.cache';

  final SharedPreferencesAsync _prefs;
  final String _key;

  /// Env namespace of [_key].
  final String env;

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
