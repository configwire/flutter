import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Prefs key for the persisted `userId`:
/// `'<prefixCache>.<Uri.encodeComponent(env)>.userId'`
/// (default prefix `'configwire'`, e.g. `'configwire.dev.userId'`).
///
/// Only the `userId` is persisted — never `customAttrs`, platform, locale,
/// or anything else. Blocked storage degrades to load-null/save-noop:
/// every helper below never throws (same pattern as
/// [SharedPreferencesCacheStore]).
String userIdKeyFor({required String env, String prefixCache = 'configwire'}) =>
    '$prefixCache.${Uri.encodeComponent(env)}.userId';

/// Loads the persisted `userId`, or null on miss/empty/error.
///
/// A stored value that is empty after trimming counts as a miss (anonymous).
///
/// Deprecated: the server ignores client-sent identity (ephemeral anonID
/// per request). Persistence stays for the compat window and will be
/// removed in the next major release; new code should not rely on it for
/// bucketing stability.
@Deprecated('Server ignores client identity; persisted userId will be removed next major.')
Future<String?> loadPersistedUserId({
  required SharedPreferencesAsync prefs,
  required String env,
  String prefixCache = 'configwire',
}) async {
  try {
    final raw = await prefs.getString(
      userIdKeyFor(env: env, prefixCache: prefixCache),
    );
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return trimmed;
  } catch (_) {
    return null;
  }
}

/// Persists `userId` (trimmed; whitespace-only clears instead).
/// Swallows ALL errors so callers never observe a throw.
///
/// Deprecated: the server ignores client-sent identity. Will be removed in
/// the next major release.
@Deprecated('Server ignores client identity; persisted userId will be removed next major.')
Future<void> savePersistedUserId({
  required SharedPreferencesAsync prefs,
  required String env,
  required String userId,
  String prefixCache = 'configwire',
}) async {
  try {
    final key = userIdKeyFor(env: env, prefixCache: prefixCache);
    final trimmed = userId.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, trimmed);
    }
  } catch (_) {
    // Swallow: blocked storage degrades to save-noop by design.
  }
}

/// Removes the persisted `userId`. Swallows ALL errors.
///
/// Deprecated: the server ignores client-sent identity. Will be removed in
/// the next major release.
@Deprecated('Server ignores client identity; persisted userId will be removed next major.')
Future<void> clearPersistedUserId({
  required SharedPreferencesAsync prefs,
  required String env,
  String prefixCache = 'configwire',
}) async {
  try {
    await prefs.remove(userIdKeyFor(env: env, prefixCache: prefixCache));
  } catch (_) {
    // Swallow: blocked storage degrades to clear-noop by design.
  }
}

/// Default `idGenerator` for `ConfigWireFlutter.createConfigWire`: a random
/// 15-char lowercase `[a-z0-9]` ID (see [generateUserId]).
///
/// Pass a custom `idGenerator` to supply the first-run ID from your own
/// source (another SDK, secure storage, tests). It runs at most once per
/// install: later launches reuse the persisted value without calling it.
///
/// Deprecated: generated IDs no longer affect server bucketing (ephemeral
/// anonID per request). Will be removed in the next major release.
@Deprecated('Generated IDs no longer affect bucketing; will be removed next major.')
String defaultIdGenerator() => generateUserId();

/// Generates a random `userId`: 15 lowercase `[a-z0-9]` chars.
///
/// Used when no persisted value exists, so every install stays stably
/// bucketed for `uid` + percentile targeting. Pass a seeded [source] in tests for determinism.
///
/// Deprecated: no longer affects server bucketing. Will be removed in the
/// next major release.
@Deprecated('Generated IDs no longer affect bucketing; will be removed next major.')
String generateUserId([Random? source]) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = source ?? Random.secure();
  return List.generate(15, (_) => alphabet[r.nextInt(alphabet.length)]).join();
}
