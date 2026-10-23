// Suite for the stable-bucket (T6) Flutter wrapper contract.
// ignore_for_file: deprecated_member_use
// (legacy `prefs:`/`prefixCache:` params are exercised deliberately here to
// pin the fallback-bucket key override, mirroring backward_compat_test.dart.)
//
// Covers, additively (existing pins in `flutter_init_test.dart` and
// `backward_compat_test.dart` are never rewritten):
//
//   (a) The T4 `CacheData.bucket` slot persists through
//       `SharedPreferencesCacheStore` in the SAME JSON row under the same
//       per-env key (`<prefix>.<env>.cache`) — no separate bucket key for
//       prefs-backed stores. Reinstall (fresh prefs) loads bucket-absent,
//       so the next cold 200 mints a new bucket.
//   (b) Non-prefs backing stores (e.g. `MemoryCacheStore`, session-only by
//       design) follow the same fallback discipline as install IDs: the
//       bucket is mirrored to prefs under `<prefix>.<env>.bucket`
//       (mirroring `userIdKeyFor`) and merged back into bucket-less rows,
//       so the persisted bucket still reaches the T5 fetch wire instead of
//       being dropped. Blocked storage degrades to load-absent/save-noop
//       and never throws (parity with the `user_store` discipline).
//   (c) Frozen behavior: `userId` still emits `?userHash=<sha256hex16>`
//       exactly as before, and the persisted bucket reaches the client
//       (`cw.bucket`, T5's `?b=` input) via the attached store.
//
// Hermetic by construction: `collectDevice: false` everywhere (no device
// seams) and no live server — `ensureInitialized: true` against
// `127.0.0.1:8090` with nothing listening fails the fetch gracefully
// (offline-first: cache load still applies, fetch errors never throw),
// exactly like the offline demo in `example/main.dart`.
import 'dart:convert';

import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Full `CacheData` fixture carrying a stable bucket beside the etag.
CacheData bucketFixture({int? bucket = 42}) => CacheData(
  etag: 'e1',
  version: 3,
  fetchedAt: DateTime.utc(2026, 9, 22),
  values: const {'launch_flag': true},
  variants: const {'checkout': 'control'},
  bucket: bucket,
);

ConfigWire memoryClient() => ConfigWire(
  apiKey: 'sk-test',
  env: 'dev',
  baseUrl: 'http://127.0.0.1:8090',
  store: MemoryCacheStore(),
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('bucket persists in the prefs store row (same key, per-env)', () {
    test('bucket 0/42/9999 round-trips beside the etag in one row', () async {
      final prefs = SharedPreferencesAsync();
      for (final bucket in [0, 42, 9999]) {
        final store = SharedPreferencesCacheStore(prefs: prefs, env: 'dev');
        await store.save(bucketFixture(bucket: bucket));
        final raw = await prefs.getString('configwire.dev.cache');
        expect(raw, isNotNull);
        final decoded = jsonDecode(raw!) as Map<String, dynamic>;
        expect(decoded['bucket'], equals(bucket));
        expect(decoded['etag'], equals('e1'));
        final loaded = await store.load();
        expect(loaded, isNotNull);
        expect(loaded!.bucket, equals(bucket));
        expect(loaded.etag, equals('e1'));
      }
    });

    test('dev and prod rows keep independent buckets', () async {
      final prefs = SharedPreferencesAsync();
      await SharedPreferencesCacheStore(
        prefs: prefs,
        env: 'dev',
      ).save(bucketFixture(bucket: 42));
      await SharedPreferencesCacheStore(
        prefs: prefs,
        env: 'prod',
      ).save(bucketFixture(bucket: 7));
      expect(
        (await SharedPreferencesCacheStore(
          prefs: prefs,
          env: 'dev',
        ).load())!.bucket,
        equals(42),
      );
      expect(
        (await SharedPreferencesCacheStore(
          prefs: prefs,
          env: 'prod',
        ).load())!.bucket,
        equals(7),
      );
    });

    test('custom prefixCache isolates the bucket row', () async {
      final prefs = SharedPreferencesAsync();
      await SharedPreferencesCacheStore(
        prefs: prefs,
        env: 'dev',
        prefixCache: 'myapp',
      ).save(bucketFixture(bucket: 42));
      expect(await prefs.getString('myapp.dev.cache'), isNotNull);
      expect(await prefs.getString('configwire.dev.cache'), isNull);
      expect(
        (await SharedPreferencesCacheStore(
          prefs: prefs,
          env: 'dev',
          prefixCache: 'myapp',
        ).load())!.bucket,
        equals(42),
      );
    });

    test('pre-bucket row without the key loads bucket-absent', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString(
        'configwire.dev.cache',
        jsonEncode({
          'etag': 'e1',
          'version': 3,
          'fetchedAt': '2026-09-22T00:00:00.000Z',
          'values': {'launch_flag': true},
          'variants': {'checkout': 'control'},
        }),
      );
      final loaded = await SharedPreferencesCacheStore(
        prefs: prefs,
        env: 'dev',
      ).load();
      expect(loaded, isNotNull);
      expect(loaded!.bucket, isNull);
      expect(loaded.etag, equals('e1'));
    });

    test('malformed bucket shapes load bucket-absent, never throw', () async {
      final prefs = SharedPreferencesAsync();
      final store = SharedPreferencesCacheStore(prefs: prefs, env: 'dev');
      for (final bad in ['42', 12.5, 10000, -1, true]) {
        await prefs.setString(
          'configwire.dev.cache',
          jsonEncode({
            'etag': 'e1',
            'version': 3,
            'fetchedAt': '2026-09-22T00:00:00.000Z',
            'values': <String, Object?>{},
            'variants': <String, String>{},
            'bucket': bad,
          }),
        );
        await expectLater(
          store.load().then((c) => c?.bucket),
          completion(isNull),
        );
      }
    });

    test(
      'blocked storage: bucket save-noop / load-absent, never throws',
      () async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        final store = SharedPreferencesCacheStore(
          prefs: _ThrowingPrefs(),
          env: 'dev',
        );
        await expectLater(store.save(bucketFixture(bucket: 42)), completes);
        await expectLater(store.load(), completion(isNull));
      },
    );

    test(
      'reinstall (fresh prefs) loads bucket-absent: next cold 200 re-mints',
      () async {
        // First install mints and persists bucket 42 in the cache row.
        final prefs = SharedPreferencesAsync();
        await SharedPreferencesCacheStore(
          prefs: prefs,
          env: 'dev',
        ).save(bucketFixture(bucket: 42));
        expect(
          (await SharedPreferencesCacheStore(
            prefs: prefs,
            env: 'dev',
          ).load())!.bucket,
          equals(42),
        );
        // Reinstall wipes app storage (prefs + cache row alike): the bucket
        // is gone and the next cold 200 mints a NEW bucket. Clearing the
        // row must never throw and must read back as absent (not stale).
        await prefs.remove('configwire.dev.cache');
        await expectLater(
          SharedPreferencesCacheStore(prefs: prefs, env: 'dev').load(),
          completion(isNull),
        );
      },
    );
  });

  group('non-prefs stores mirror the bucket via the prefs fallback', () {
    test(
      'seeded fallback bucket reaches the memory row at configure',
      () async {
        final prefs = SharedPreferencesAsync();
        await prefs.setString('configwire.dev.bucket', '42');
        final cw = memoryClient();
        await cw.configureFlutter(
          collectDevice: false,
          idGenerator: () => 'abc123def456ghi',
        );
        final row = await cw.store.load();
        expect(row, isNotNull);
        expect(row!.bucket, equals(42));
        // The fallback key follows the userIdKeyFor namespacing scheme.
        expect(await prefs.getString('configwire.dev.bucket'), equals('42'));
        await cw.dispose();
      },
    );

    test('row bucket wins over a stale fallback bucket', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString('configwire.dev.bucket', '7');
      final cw = memoryClient();
      await cw.configureFlutter(
        collectDevice: false,
        idGenerator: () => 'abc123def456ghi',
      );
      // A fresher row (e.g. a just-completed fetch) outranks the fallback.
      await cw.store.save(bucketFixture(bucket: 42));
      final row = await cw.store.load();
      expect(row!.bucket, equals(42));
      // ... and the winning bucket is mirrored back to the fallback key.
      expect(await prefs.getString('configwire.dev.bucket'), equals('42'));
      await cw.dispose();
    });

    test('malformed fallback bucket is ignored, never throws', () async {
      final prefs = SharedPreferencesAsync();
      final cw = memoryClient();
      await cw.configureFlutter(
        collectDevice: false,
        idGenerator: () => 'abc123def456ghi',
      );
      for (final bad in ['abc', '007', '10000', '-1', ' 12 ', '']) {
        await prefs.setString('configwire.dev.bucket', bad);
        final row = await cw.store.load();
        expect(row?.bucket, isNull);
      }
      await cw.dispose();
    });

    test(
      'blocked prefs: memory store stays session-only, never throws',
      () async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        final cw = ConfigWire(
          apiKey: 'sk-test',
          env: 'dev',
          baseUrl: 'http://127.0.0.1:8090',
          store: MemoryCacheStore(),
        );
        // Blocked storage must not break configure even though the bucket
        // fallback backend throws on every call: the install still gets a
        // session identity and an (empty) session row, with no bucket.
        await cw.configureFlutter(
          prefs: _ThrowingPrefs(),
          collectDevice: false,
          idGenerator: () => 'abc123def456ghi',
        );
        expect(cw.targeting.userId, equals('abc123def456ghi'));
        final row = await cw.store.load();
        expect(row?.bucket, isNull);
        await cw.dispose();
      },
    );

    test(
      'legacy prefixCache override governs the fallback bucket key',
      () async {
        final prefs = SharedPreferencesAsync();
        await prefs.setString('custom.dev.bucket', '9');
        final cw = memoryClient();
        await cw.configureFlutter(
          prefs: prefs,
          prefixCache: 'custom',
          collectDevice: false,
          idGenerator: () => 'abc123def456ghi',
        );
        expect((await cw.store.load())!.bucket, equals(9));
        // Custom prefix isolates: the default key stays empty.
        expect(await prefs.getString('configwire.dev.bucket'), isNull);
        await cw.dispose();
      },
    );
  });

  group('frozen emission + wrapper-to-wire bucket handoff', () {
    test('userId still emits ?userHash= with a bucket persisted', () async {
      final prefs = SharedPreferencesAsync();
      await SharedPreferencesCacheStore(
        prefs: prefs,
        env: 'dev',
      ).save(bucketFixture(bucket: 42));
      final cw = ConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        store: SharedPreferencesCacheStore(env: 'dev'),
      );
      await cw.configureFlutter(
        collectDevice: false,
        idGenerator: () => 'user-9',
      );
      // Frozen: userId -> ?userHash=<sha256hex16>, never raw ?uid=.
      // The ?b= send itself is T5's fetch-wire merge (dart/) reading the
      // persisted row; the server applies ?b= > ?userHash= precedence.
      final q = cw.targeting.toQueryParameters();
      expect(q.containsKey('uid'), isFalse);
      expect(q['userHash'], equals(sha256Hex16('user-9')));
      await cw.dispose();
    });

    test(
      'persisted row bucket reaches cw.bucket on init (T5 ?b= input)',
      () async {
        final prefs = SharedPreferencesAsync();
        await SharedPreferencesCacheStore(
          prefs: prefs,
          env: 'dev',
        ).save(bucketFixture(bucket: 42));
        final cw = ConfigWire(
          apiKey: 'sk-test',
          env: 'dev',
          baseUrl: 'http://127.0.0.1:8090',
          store: SharedPreferencesCacheStore(env: 'dev'),
        );
        // No server is listening: the forced fetch fails gracefully and
        // keeps the cache-loaded bucket (offline-first, never throws).
        await cw.configureFlutter(
          collectDevice: false,
          idGenerator: () => 'abc123def456ghi',
          ensureInitialized: true,
        );
        expect(cw.bucket, equals(42));
        expect(cw.etag, equals('e1'));
        await cw.dispose();
      },
    );

    test('memory store + seeded fallback reaches cw.bucket on init', () async {
      await SharedPreferencesAsync().setString('configwire.dev.bucket', '77');
      final cw = memoryClient();
      await cw.configureFlutter(
        collectDevice: false,
        idGenerator: () => 'abc123def456ghi',
        ensureInitialized: true,
      );
      expect(cw.bucket, equals(77));
      await cw.dispose();
    });
  });
}

/// Simulates blocked storage: every backend call throws. Mirrors the
/// `_ThrowingPrefs` probe in `prefs_store_test.dart`.
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
