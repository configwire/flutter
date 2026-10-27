// Suite for `SharedPreferencesCacheStore`.
//
// Target API under test:
//   SharedPreferencesCacheStore({
//     required SharedPreferencesAsync prefs,
//     String? apiKey,
//     String? env,
//     String prefixCache = 'configwire',
//   })
// At least one of `apiKey`/`env` is required. Prefs key =
// `'<prefixCache>.<Uri.encodeComponent(namespace)>.cache'` where
// `namespace` is the first 8 chars of the SDK key when `apiKey:` is given,
// else the legacy `env` string verbatim (byte-identical to before, e.g.
// default `configwire.dev.cache` for `env: 'dev'`, and default
// `configwire.cw-01234.cache` for the `kApiKeyA` fixture);
// `load()` returns `CacheData?` (null on miss/corrupt, never throws);
// `save(CacheData)` persists and swallows ALL errors.
//
// `keyPrefixOf` mirrors the server's `KeyPrefix` (`configwire/ingest/hash.go`):
// first 8 chars, or the whole key when shorter.
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

/// Realistic SDK-key fixtures (`'cw-'` + 24 base62).
const kApiKeyA = 'cw-0123456789ABCDEFGHJKLMNP';
const kApiKeyB = 'cw-QRSTUVWXYZabcdefghijklmn';

/// First-8 prefixes of the fixtures above.
const kPrefixA = 'cw-01234';
const kPrefixB = 'cw-QRSTU';

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

  group('keyPrefixOf', () {
    test('returns the first 8 chars of a full SDK key', () {
      expect(keyPrefixOf(kApiKeyA), equals(kPrefixA));
      expect(keyPrefixOf(kApiKeyB), equals(kPrefixB));
    });

    test('short keys return whole', () {
      expect(keyPrefixOf(''), equals(''));
      expect(keyPrefixOf('a'), equals('a'));
      expect(keyPrefixOf('1234567'), equals('1234567'));
      expect(keyPrefixOf('12345678'), equals('12345678'));
    });

    test('exactly-9-char keys truncate to 8', () {
      expect(keyPrefixOf('123456789'), equals('12345678'));
    });
  });

  group('SharedPreferencesCacheStore', () {
    test('round-trip save→load equals original', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final store = SharedPreferencesCacheStore(prefs: prefs, apiKey: kApiKeyA);

      final original = fixture();
      await store.save(original);

      // Key asserted namespaced by SDK-key prefix with the default prefix.
      final raw = await prefs.getString('configwire.$kPrefixA.cache');
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
        apiKey: kApiKeyA,
      );

      await expectLater(store.load(), completion(isNull));
    });

    test('corrupt payload loads null without throwing', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'configwire.$kPrefixA.cache': '{bad',
          });
      final store = SharedPreferencesCacheStore(
        prefs: SharedPreferencesAsync(),
        apiKey: kApiKeyA,
      );

      await expectLater(store.load(), completion(isNull));
    });

    test('custom prefixCache isolates the key', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final store = SharedPreferencesCacheStore(
        prefs: prefs,
        apiKey: kApiKeyA,
        prefixCache: 'myapp',
      );

      await store.save(fixture());

      expect(await prefs.getString('myapp.$kPrefixA.cache'), isNotNull);
      expect(await prefs.getString('configwire.$kPrefixA.cache'), isNull);
      final loaded = await store.load();
      expect(loaded, isNotNull);
      expectSameCacheData(loaded!, fixture());
    });

    test('different keys isolate; same key shares', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      await SharedPreferencesCacheStore(
        prefs: prefs,
        apiKey: kApiKeyA,
      ).save(fixture());

      // A different SDK key reads a different row (cold).
      await expectLater(
        SharedPreferencesCacheStore(prefs: prefs, apiKey: kApiKeyB).load(),
        completion(isNull),
      );
      // The same SDK key shares the row.
      final loaded = await SharedPreferencesCacheStore(
        prefs: prefs,
        apiKey: kApiKeyA,
      ).load();
      expect(loaded, isNotNull);
      expectSameCacheData(loaded!, fixture());
    });

    test('prefix is URI-encoded in the default key', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      // First-8 `a/b cDEF` exercises the encodeComponent path; real SDK
      // keys are ASCII `cw-`+base62 so no encoding applies to them.
      final store = SharedPreferencesCacheStore(
        prefs: prefs,
        apiKey: 'a/b cDEFGHJKLMNOP',
      );

      await store.save(fixture());

      expect(await prefs.getString('configwire.a%2Fb%20cDEF.cache'), isNotNull);
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
        apiKey: kApiKeyA,
      );

      await expectLater(store.save(fixture()), completes);
      await expectLater(store.load(), completion(isNull));
    });

    test('requires apiKey or env', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      // Runtime ArgumentError in debug AND release (no assert-only guard).
      expect(
        () => SharedPreferencesCacheStore(prefs: SharedPreferencesAsync()),
        throwsArgumentError,
      );
      expect(() => storeNamespaceFor(), throwsArgumentError);
    });
  });

  group('SharedPreferencesCacheStore legacy env namespace', () {
    test('env: round-trip uses the byte-identical legacy key', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final store = SharedPreferencesCacheStore(prefs: prefs, env: 'dev');

      await store.save(fixture());

      // Byte-identical to before: <prefix>.<encodeComponent(env)>.cache.
      final raw = await prefs.getString('configwire.dev.cache');
      expect(raw, isNotNull);

      final loaded = await store.load();
      expect(loaded, isNotNull);
      expectSameCacheData(loaded!, fixture());
    });

    test('env: custom prefixCache isolates the legacy key', () async {
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
    });

    test('env: different envs isolate; same env shares', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      await SharedPreferencesCacheStore(
        prefs: prefs,
        env: 'dev',
      ).save(fixture());

      await expectLater(
        SharedPreferencesCacheStore(prefs: prefs, env: 'prod').load(),
        completion(isNull),
      );
      final loaded = await SharedPreferencesCacheStore(
        prefs: prefs,
        env: 'dev',
      ).load();
      expect(loaded, isNotNull);
      expectSameCacheData(loaded!, fixture());
    });

    test('env: special chars are URI-encoded verbatim', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final store = SharedPreferencesCacheStore(prefs: prefs, env: 'a/b c');

      await store.save(fixture());

      expect(await prefs.getString('configwire.a%2Fb%20c.cache'), isNotNull);
    });

    test('apiKey wins when both are given', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();
      final store = SharedPreferencesCacheStore(
        prefs: prefs,
        apiKey: kApiKeyA,
        env: 'dev',
      );

      await store.save(fixture());

      expect(await prefs.getString('configwire.$kPrefixA.cache'), isNotNull);
      expect(await prefs.getString('configwire.dev.cache'), isNull);
    });
  });
}
