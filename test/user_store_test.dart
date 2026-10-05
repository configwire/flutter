// Suite for the persisted-`userId` helpers in `lib/src/user_store.dart`.
//
// Prefs key = `'<prefixCache>.<Uri.encodeComponent(env)>.userId'`
// (default prefix `configwire`, e.g. `configwire.dev.userId`);
// `loadPersistedUserId` returns `String?` (null on miss/empty/error, never
// throws); `save`/`clear` swallow ALL errors. Mirrors the
// `prefs_store_test.dart` techniques: a fresh
// `InMemorySharedPreferencesAsync` per test, plus `_ThrowingPrefs` for
// blocked storage.
import 'dart:math';

import 'package:configwire_flutter/src/user_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

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

  group('user_store', () {
    test('round-trip save→load equals original', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();

      await savePersistedUserId(prefs: prefs, env: 'dev', userId: 'user-7');

      // Key asserted namespaced per env with the default prefix.
      expect(await prefs.getString('configwire.dev.userId'), 'user-7');
      expect(
        await loadPersistedUserId(prefs: prefs, env: 'dev'),
        'user-7',
      );
    });

    test('missing key loads null without throwing', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();

      await expectLater(
        loadPersistedUserId(
          prefs: SharedPreferencesAsync(),
          env: 'dev',
        ),
        completion(isNull),
      );
    });

    test('custom prefixCache isolates the key', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();

      await savePersistedUserId(
        prefs: prefs,
        env: 'dev',
        userId: 'user-7',
        prefixCache: 'myapp',
      );

      expect(await prefs.getString('myapp.dev.userId'), 'user-7');
      expect(await prefs.getString('configwire.dev.userId'), isNull);
      expect(
        await loadPersistedUserId(
          prefs: prefs,
          env: 'dev',
          prefixCache: 'myapp',
        ),
        'user-7',
      );
      // Default prefix sees nothing.
      expect(
        await loadPersistedUserId(prefs: prefs, env: 'dev'),
        isNull,
      );
    });

    test('env is URI-encoded in the default key', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();

      await savePersistedUserId(prefs: prefs, env: 'a/b c', userId: 'user-7');

      expect(
        await prefs.getString('configwire.a%2Fb%20c.userId'),
        'user-7',
      );
      expect(
        await loadPersistedUserId(prefs: prefs, env: 'a/b c'),
        'user-7',
      );
    });

    test('clear removes the persisted value', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = SharedPreferencesAsync();

      await savePersistedUserId(prefs: prefs, env: 'dev', userId: 'user-7');
      expect(
        await loadPersistedUserId(prefs: prefs, env: 'dev'),
        'user-7',
      );

      await clearPersistedUserId(prefs: prefs, env: 'dev');
      expect(await loadPersistedUserId(prefs: prefs, env: 'dev'), isNull);
      expect(await prefs.getString('configwire.dev.userId'), isNull);
    });

    test('userIdKeyFor builds the new key scheme', () {
      expect(userIdKeyFor(env: 'dev'), 'configwire.dev.userId');
      expect(
        userIdKeyFor(env: 'dev', prefixCache: 'myapp'),
        'myapp.dev.userId',
      );
      expect(
        userIdKeyFor(env: 'a/b c'),
        'configwire.a%2Fb%20c.userId',
      );
    });

    test('failing prefs: save/clear swallow errors, load returns null',
        () async {
      // Seeded only so the `_ThrowingPrefs` super-constructor finds a
      // platform; every storage call below still throws by override.
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final prefs = _ThrowingPrefs();

      await expectLater(
        savePersistedUserId(prefs: prefs, env: 'dev', userId: 'user-7'),
        completes,
      );
      await expectLater(
        clearPersistedUserId(prefs: prefs, env: 'dev'),
        completes,
      );
      await expectLater(
        loadPersistedUserId(prefs: prefs, env: 'dev'),
        completion(isNull),
      );
    });

    test('defaultIdGenerator produces simple lowercase IDs', () {
      expect(defaultIdGenerator(), matches(RegExp(r'^[a-z0-9]{15}$')));
    });

    test('generateUserId produces simple lowercase IDs', () {
      final simpleId = RegExp(r'^[a-z0-9]{15}$');
      expect(generateUserId(), matches(simpleId));
    });

    test('generateUserId is unique and deterministic with a seed', () {
      final simpleId = RegExp(r'^[a-z0-9]{15}$');
      final seen = <String>{generateUserId(), generateUserId()};
      expect(seen, hasLength(2));
      for (final id in seen) {
        expect(id, matches(simpleId));
      }
      // Same seed reproduces the same ID.
      expect(
        generateUserId(Random(42)),
        generateUserId(Random(42)),
      );
    });
  });
}
