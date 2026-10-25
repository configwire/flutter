// Suite for the Flutter dual-key clear-on-logout contract.
//
// `ConfigWireFlutter.clearBucket(cw)` mirrors Dart's `clearBucket` (nulls
// the in-memory bucket, re-persists the row with `bucket: null`, next
// fetch sends no `?b=`) and additionally clears the prefs fallback key
// `<prefix>.<env>.bucket` via `clearPersistedBucket`, so both keys are
// cleared whatever backing store is attached. Row-wins precedence,
// reinstall-wipes-row semantics, and per-env isolation are preserved:
// clearing one env never touches another. Blocked storage degrades to a
// memory-only clear and never throws.
//
// Hermetic by construction: `collectDevice: false` everywhere (no device
// seams), `InMemorySharedPreferencesAsync` doubles, and `MockClient` for
// the wire assertion — no live server.
import 'dart:convert';

import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

String fetch200Bucket({String etag = 'e1', int? bucket}) {
  final m = <String, Object?>{
    'version': 1,
    'etag': etag,
    'values': {'k': 'v'},
    'variants': <String, String>{},
    'fetchAt': '2026-09-22T00:00:00.000Z',
  };
  if (bucket != null) m['bucket'] = bucket;
  return jsonEncode(m);
}

CacheData bucketRow({int? bucket = 42}) => CacheData(
  etag: 'e1',
  version: 3,
  fetchedAt: DateTime.utc(2026, 9, 22),
  values: const {'k': 'v'},
  variants: const {},
  bucket: bucket,
);

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

/// Simulates a blocked [CacheStore]: every op throws.
class _ThrowingStore implements CacheStore {
  @override
  Future<CacheData?> load() async => throw StateError('blocked');

  @override
  Future<void> save(CacheData data) async => throw StateError('blocked');
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('clearPersistedBucket helper', () {
    test('removes the fallback key, per-env isolated', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString('configwire.dev.bucket', '42');
      await prefs.setString('configwire.prod.bucket', '7');

      await clearPersistedBucket(prefs: prefs, env: 'dev');

      expect(await prefs.getString('configwire.dev.bucket'), isNull);
      expect(await prefs.getString('configwire.prod.bucket'), equals('7'));
    });

    test('never throws on blocked storage', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      await expectLater(
        clearPersistedBucket(prefs: _ThrowingPrefs(), env: 'dev'),
        completes,
      );
    });
  });

  group('ConfigWireFlutter.clearBucket (dual-key clear-on-logout)', () {
    test(
      'prefs store: clears in-memory bucket, row bucket, and fallback',
      () async {
        final prefs = SharedPreferencesAsync();
        await SharedPreferencesCacheStore(
          prefs: prefs,
          env: 'dev',
        ).save(bucketRow(bucket: 42));
        // Stray fallback from an earlier non-prefs configuration must go too.
        await prefs.setString('configwire.dev.bucket', '42');
        final cw = ConfigWire(
          apiKey: 'sk-test',
          env: 'dev',
          baseUrl: 'http://127.0.0.1:8090',
          store: SharedPreferencesCacheStore(env: 'dev'),
        );
        // No server is listening: the forced fetch fails gracefully and keeps
        // the cache-loaded bucket (offline-first, never throws).
        await cw.configureFlutter(
          collectDevice: false,
          ensureInitialized: true,
        );
        expect(cw.bucket, equals(42));

        await ConfigWireFlutter.clearBucket(cw);

        expect(cw.bucket, isNull);
        final row = await SharedPreferencesCacheStore(
          prefs: prefs,
          env: 'dev',
        ).load();
        expect(row, isNotNull);
        expect(row!.bucket, isNull);
        // Values/etag survive the clear; only the bucket slot is nulled.
        expect(row.etag, equals('e1'));
        expect(await prefs.getString('configwire.dev.bucket'), isNull);
        await cw.dispose();
      },
    );

    test(
      'memory store: clears in-memory bucket and the fallback key',
      () async {
        final prefs = SharedPreferencesAsync();
        await prefs.setString('configwire.dev.bucket', '77');
        final cw = ConfigWire(
          apiKey: 'sk-test',
          env: 'dev',
          baseUrl: 'http://127.0.0.1:8090',
          store: MemoryCacheStore(),
        );
        await cw.configureFlutter(
          collectDevice: false,
          ensureInitialized: true,
        );
        expect(cw.bucket, equals(77));

        await ConfigWireFlutter.clearBucket(cw);

        expect(cw.bucket, isNull);
        expect((await cw.store.load())?.bucket, isNull);
        expect(await prefs.getString('configwire.dev.bucket'), isNull);
        await cw.dispose();
      },
    );

    test(
      'per-env isolation: clearing dev leaves prod row + fallback intact',
      () async {
        final prefs = SharedPreferencesAsync();
        await SharedPreferencesCacheStore(
          prefs: prefs,
          env: 'dev',
        ).save(bucketRow(bucket: 42));
        await SharedPreferencesCacheStore(
          prefs: prefs,
          env: 'prod',
        ).save(bucketRow(bucket: 7));
        await prefs.setString('configwire.dev.bucket', '42');
        await prefs.setString('configwire.prod.bucket', '7');
        final cw = ConfigWire(
          apiKey: 'sk-test',
          env: 'dev',
          baseUrl: 'http://127.0.0.1:8090',
          store: SharedPreferencesCacheStore(env: 'dev'),
        );
        await cw.configureFlutter(collectDevice: false);

        await ConfigWireFlutter.clearBucket(cw);

        expect(cw.bucket, isNull);
        expect(
          (await SharedPreferencesCacheStore(
            prefs: prefs,
            env: 'prod',
          ).load())!.bucket,
          equals(7),
        );
        expect(await prefs.getString('configwire.prod.bucket'), equals('7'));
        await cw.dispose();
      },
    );

    test('never throws on blocked storage, still clears in-memory', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      final cw = ConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        store: _ThrowingStore(),
      );
      await cw.configureFlutter(prefs: _ThrowingPrefs(), collectDevice: false);

      await expectLater(
        ConfigWireFlutter.clearBucket(cw, prefs: _ThrowingPrefs()),
        completes,
      );
      expect(cw.bucket, isNull);
      await cw.dispose();
    });

    test('next fetch after clear sends no ?b=', () async {
      String? lastB;
      final mock = MockClient((req) async {
        if (req.method == 'POST') {
          return http.Response('{"accepted":1,"status":202}', 202);
        }
        lastB = req.url.queryParameters['b'];
        return http.Response(fetch200Bucket(bucket: 42), 200);
      });
      final cw = ConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        client: mock,
        store: MemoryCacheStore(),
        minimumFetchInterval: Duration.zero,
      );
      await cw.configureFlutter(collectDevice: false);
      expect(await cw.fetchAndActivate(), isTrue);
      expect(cw.bucket, equals(42));

      await ConfigWireFlutter.clearBucket(cw);
      expect(cw.bucket, isNull);

      expect(await cw.fetchAndActivate(), isTrue);
      expect(lastB, isNull);
      await cw.dispose();
    });
  });
}
