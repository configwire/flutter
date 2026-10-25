// Backward-compat: old 0.2.x call shapes still work (compile + pass).
//
// Covers the legacy entry points removed from docs but kept as shims:
//   (a) `ConfigWireFlutter.createConfigWire(...)` one-shot factory;
//   (b) `cw.configureFlutter(prefs: ..., prefixCache: ...)` custom-key persistence;
//   (c) explicit Memory-store + `configureFlutter()` stays bucket-capable
//       via the prefs fallback;
//   (d) bare `ConfigWire(...)` + `configureFlutter()` gets the default store.
//
// Targeting is always anonymous in every case below; bucketing rides `?b=`.
//
// Hermetic by construction: every case passes `collectDevice: false` (no
// device seams) and `ensureInitialized: false` where the factory offers it
// (no network — with no server listening only targeting/persistence are
// asserted). The async prefs backend is seeded per test via
// `InMemorySharedPreferencesAsync` so the default
// `SharedPreferencesAsync()` construction never throws. Every case ends
// with `await cw.dispose()` cleanup, mirroring `flutter_init_test.dart`.
import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

ConfigWire _testClient({Map<String, Object?> defaults = const {}}) {
  return ConfigWire(
    apiKey: 'sk-test',
    env: 'dev',
    baseUrl: 'http://127.0.0.1:8090',
    defaults: defaults,
    store: SharedPreferencesCacheStore(env: 'dev'),
  );
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('(a) createConfigWire resolves anonymous targeting', () async {
    var cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();

    // Relaunch resolves identically: still anonymous, still no identity.
    cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
    await cw.dispose();
  });

  test('(a) createConfigWire carries customAttrs by default', () async {
    final cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });

  test(
    '(b) configureFlutter(prefs:, prefixCache:) honors the custom key',
    () async {
      final customPrefs = SharedPreferencesAsync();
      await customPrefs.setString('custom.dev.bucket', '9');

      final first = _testClient();
      await first.configureFlutter(
        prefs: customPrefs,
        prefixCache: 'custom',
        collectDevice: false,
      );
      expect(first.targeting.toQueryParameters(), isNot(contains('userHash')));
      // Custom prefix isolates: the default key stays empty.
      expect(await customPrefs.getString('configwire.dev.bucket'), isNull);
      await first.dispose();

      final second = _testClient();
      await second.configureFlutter(
        prefs: customPrefs,
        prefixCache: 'custom',
        collectDevice: false,
      );
      expect(second.targeting.toQueryParameters(), isNot(contains('userHash')));
      await second.dispose();
    },
  );

  test(
    '(c) Memory-store + configureFlutter stays bucket-capable via fallback',
    () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString('configwire.dev.bucket', '42');
      final first = ConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        store: MemoryCacheStore(),
      );
      await first.configureFlutter(collectDevice: false);
      expect(first.targeting.toQueryParameters(), isNot(contains('userHash')));
      // Fallback bucket still reaches the memory row.
      expect((await first.store.load())?.bucket, equals(42));
      await first.dispose();

      // Relaunch with a fresh Memory store reuses the fallback bucket.
      final second = ConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        store: MemoryCacheStore(),
      );
      await second.configureFlutter(collectDevice: false);
      expect(second.targeting.toQueryParameters(), isNot(contains('userHash')));
      expect((await second.store.load())?.bucket, equals(42));
      await second.dispose();
    },
  );

  test(
    '(d) bare ConfigWire + configureFlutter gets the default store',
    () async {
      final cw = ConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
      );
      await cw.configureFlutter(collectDevice: false);
      expect(cw.store is SharedPreferencesCacheStore, isTrue);
      expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
      await cw.dispose();

      // Relaunch resolves identically.
      final relaunch = ConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
      );
      await relaunch.configureFlutter(collectDevice: false);
      await relaunch.dispose();
    },
  );
}
