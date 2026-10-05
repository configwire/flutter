// Suite for `SharedPreferencesCacheStore`.
//
// Target API under test:
//   SharedPreferencesCacheStore({
//     required SharedPreferencesAsync prefs,
//     required String env,
//     String prefixCache = 'configwire',
//   })
// Prefs key = `'<prefixCache>.<Uri.encodeComponent(env)>.cache'`
// (default `configwire.dev.cache`);
// `load()` returns `CacheData?` (null on miss/corrupt, never throws);
// `save(CacheData)` persists and swallows ALL errors.
//
// Test techniques:
// - `SharedPreferencesAsyncPlatform.instance` is pointed at a fresh
//   `InMemorySharedPreferencesAsync` per test (the legacy
//   `SharedPreferences.setMockInitialValues` mock only backs the sync API
//   and no longer wires the async platform in shared_preferences 2.5.5).
// - Blocked storage (private mode / denied quota) is simulated with
//   `_ThrowingPrefs`, a `SharedPreferencesAsync` subclass whose storage
//   calls throw; `save` must swallow that and complete normally, and
//   `load` must resolve null instead of throwing.
import 'package:configwire/configwire.dart';
import 'package:configwire_flutter/src/prefs_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Full `CacheData` fixture shared by every case.
CacheData fixture() => CacheData(
  etag: 'e1',
  version: 3,
  fetchedAt: DateTime.utc(2026, 9, 22),
  values: {'launch_flag': true, 'retries': 2},
  variants: {'checkout': 'control'},
);

void expectSameCacheData(CacheData actual, CacheData expected) {
  expect(actual.etag, expected.etag);
  expect(actual.version, expected.version);
  expect(actual.fetchedAt.toUtc(), expected.fetchedAt.toUtc());
  expect(actual.values, expected.values);
  expect(actual.variants, expected.variants);
}

/// Simulates blocked storage: every backend call throws.
class _ThrowingPrefs extends SharedPreferencesAsync {
  @override
  Future<String?> getString(String key) =>
      Future.error(StateError('blocked storage'));

  @override
  Future<void> setString(String key, String value) =>
      Future.error(StateError('blocked storage'));

  @override
  Future<void> remove(String key) =>
      Future.error(StateError('blocked storage'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesCacheStore', () {
    test('round-trip save→load equals original', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final store = SharedPreferencesCacheStore(prefs: prefs, env: 'dev');

      final original = fixture();
      await store.save(original);

      // Key asserted namespaced per env with the default prefix.
      final raw = await prefs.getString('configwire.dev.cache');
      expect(raw, isNotNull);

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expectSameCacheData(loaded!, original);
    });

    test('missing key loads null without throwing', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final store = SharedPreferencesCacheStore(
        prefs: SharedPreferencesAsync(),
        env: 'dev',
      );

      await expectLater(store.load(), completion(isNull));
    });

    test('corrupt payload loads null without throwing', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'configwire.dev.cache': '{bad',
          });
      final store = SharedPreferencesCacheStore(
        prefs: SharedPreferencesAsync(),
        env: 'dev',
      );

      await expectLater(store.load(), completion(isNull));
    });

    test('custom prefixCache isolates the key', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final store = SharedPreferencesCacheStore(
        prefs: prefs,
        env: 'dev',
        prefixCache: 'myapp',
      );

      await store.save(fixture());

      expect(await prefs.getString('myapp.dev.cache'), isNotNull);
      expect(await prefs.getString('configwire.dev.cache'), isNull);
      final loaded = await store.load();
      expect(loaded, isNotNull);
      expectSameCacheData(loaded!, fixture());
    });

    test('env is URI-encoded in the default key', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final store = SharedPreferencesCacheStore(
        prefs: prefs,
        env: 'a/b c',
      );

      await store.save(fixture());

      expect(
        await prefs.getString('configwire.a%2Fb%20c.cache'),
        isNotNull,
      );
      final loaded = await store.load();
      expect(loaded, isNotNull);
      expectSameCacheData(loaded!, fixture());
    });

    test('failing prefs: save swallows errors, load returns null', () async {
      // Seeded only so the `_ThrowingPrefs` super-constructor finds a
      // platform; every storage call below still throws by override.
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final store = SharedPreferencesCacheStore(
        prefs: _ThrowingPrefs(),
        env: 'dev',
      );

      await expectLater(store.save(fixture()), completes);
      await expectLater(store.load(), completion(isNull));
    });
  });
}
