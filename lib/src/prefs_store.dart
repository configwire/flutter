// ignore_for_file: prefer_initializing_formals
// (constructor param `prefs` must keep its public name for the test API;
// the backing field is intentionally private, so no initializing formal.)
import 'dart:convert';

import 'package:configwire/configwire.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [CacheStore] backed by [SharedPreferencesAsync].
///
/// Prefs key: `cacheKey ?? 'configwire.cache.<Uri.encodeComponent(env)>'`.
///
/// Divergence from [CacheStore.save]'s may-throw permission: this store
/// swallows ALL save errors (blocked storage, denied quota, corrupt
/// backend) and completes normally, so callers never observe a throw.
class SharedPreferencesCacheStore implements CacheStore {
  SharedPreferencesCacheStore({
    required SharedPreferencesAsync prefs,
    required String env,
    String? cacheKey,
  }) : _prefs = prefs,
       _key = cacheKey ?? 'configwire.cache.${Uri.encodeComponent(env)}';

  final SharedPreferencesAsync _prefs;
  final String _key;

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
