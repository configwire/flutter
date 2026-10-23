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
/// Only the `sha256hex16` hash of this value travels on the wire
/// and the raw value is never persisted server-side.
///
/// Deprecated: the server ignores `userHash` for bucketing
/// (accepted-but-ignored, `X-CW-Deprecated-userHash` compat header
/// stamped). Persistence stays for the compat window; new code should
/// stop sending identity and rely on the stable `?b=` bucket. Will be
/// removed in the next major release.
@Deprecated(
  'Server ignores userHash for bucketing (accepted-but-ignored, compat header stamped); '
  'stop sending userId and rely on the stable ?b= bucket; will be removed in the next major release.',
)
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
/// Deprecated: the server ignores `userHash` for bucketing
/// (accepted-but-ignored). Persistence stays for the compat window; will
/// be removed in the next major release.
@Deprecated(
  'Server ignores userHash for bucketing (accepted-but-ignored, compat header stamped); '
  'stop sending userId and rely on the stable ?b= bucket; will be removed in the next major release.',
)
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
/// Deprecated: the server ignores `userHash` for bucketing
/// (accepted-but-ignored). Will be removed in the next major release.
@Deprecated(
  'Server ignores userHash for bucketing (accepted-but-ignored, compat header stamped); '
  'stop sending userId and rely on the stable ?b= bucket; will be removed in the next major release.',
)
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

/// Default `idGenerator` for `configureFlutter`: a random
/// 15-char lowercase `[a-z0-9]` ID (see [generateUserId]).
///
/// Pass a custom `idGenerator` to supply the first-run ID from your own
/// source (another SDK, secure storage, tests). It runs at most once per
/// install: later launches reuse the persisted value without calling it.
///
/// Deprecated: the server ignores `userHash` for bucketing
/// (accepted-but-ignored); generated IDs stay for the compat window only.
/// Stop sending identity and rely on the stable `?b=` bucket. Will be
/// removed in the next major release.
@Deprecated(
  'Server ignores userHash for bucketing (accepted-but-ignored, compat header stamped); '
  'stop sending userId and rely on the stable ?b= bucket; will be removed in the next major release.',
)
String defaultIdGenerator() => generateUserId();

/// Generates a random `userId`: 15 lowercase `[a-z0-9]` chars.
///
/// Used when no persisted value exists, so every install stays stably
/// bucketed for `userHash` + percentile targeting. Pass a seeded [source] in tests for determinism.
///
/// Deprecated: the server ignores `userHash` for bucketing
/// (accepted-but-ignored). Will be removed in the next major release.
@Deprecated(
  'Server ignores userHash for bucketing (accepted-but-ignored, compat header stamped); '
  'stop sending userId and rely on the stable ?b= bucket; will be removed in the next major release.',
)
String generateUserId([Random? source]) {
  const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = source ?? Random.secure();
  return List.generate(15, (_) => alphabet[r.nextInt(alphabet.length)]).join();
}
