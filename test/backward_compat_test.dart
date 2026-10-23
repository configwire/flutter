// ignore_for_file: deprecated_member_use
// Backward-compat: old 0.2.x call shapes still work (compile + pass).
//
// Covers the legacy entry points removed from docs but kept as shims:
//   (a) `ConfigWireFlutter.createConfigWire(...)` one-shot factory;
//   (b) `cw.configureFlutter(prefs: ..., prefixCache: ...)` custom-key persistence;
//   (c) explicit Memory-store + `configureFlutter()` stays STABLE via prefs fallback;
//   (d) bare `ConfigWire(...)` + `configureFlutter()` persists under the default key.
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

  final simpleId = RegExp(r'^[a-z0-9]{15}$');

  test('(a) createConfigWire returns a ConfigWire with stable userId',
      () async {
    var calls = 0;
    String generator() {
      calls++;
      return 'abc123def456ghi';
    }

    var cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      customAttrs: const {'plan': 'pro'},
      idGenerator: generator,
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, 'abc123def456ghi');
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    expect(calls, 1);
    expect(
      await loadPersistedUserId(prefs: SharedPreferencesAsync(), env: 'dev'),
      'abc123def456ghi',
    );
    await cw.dispose();

    // Relaunch reuses the pinned ID without calling the generator again.
    cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      customAttrs: const {'plan': 'pro'},
      idGenerator: generator,
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, 'abc123def456ghi');
    expect(calls, 1);
    await cw.dispose();
  });

  test('(a) createConfigWire generates a 15-char ID by default', () async {
    final cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, matches(simpleId));
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });

  test('(b) configureFlutter(prefs:, prefixCache:) persists under custom key',
      () async {
    final customPrefs = SharedPreferencesAsync();
    var calls = 0;
    String generator() {
      calls++;
      return 'abc123def456ghi';
    }

    final first = _testClient();
    await first.configureFlutter(
      prefs: customPrefs,
      prefixCache: 'custom',
      collectDevice: false,
      idGenerator: generator,
    );
    expect(first.targeting.userId, 'abc123def456ghi');
    expect(calls, 1);
    expect(await customPrefs.getString('custom.dev.userId'), 'abc123def456ghi');
    // Custom prefix isolates: the default key stays empty.
    expect(await customPrefs.getString('configwire.dev.userId'), isNull);
    await first.dispose();

    final second = _testClient();
    await second.configureFlutter(
      prefs: customPrefs,
      prefixCache: 'custom',
      collectDevice: false,
      idGenerator: generator,
    );
    expect(second.targeting.userId, 'abc123def456ghi');
    expect(
      calls,
      1,
      reason: 'persisted ID under custom key must be reused, '
          'generator not called again',
    );
    await second.dispose();
  });

  test('(c) Memory-store + configureFlutter stays stable via prefs fallback',
      () async {
    final first = ConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      store: MemoryCacheStore(),
    );
    await first.configureFlutter(collectDevice: false);
    expect(first.targeting.userId, matches(simpleId));
    expect(first.targeting.userId, isNotEmpty);
    final pinned = first.targeting.userId;
    // Persisted via the prefs fallback even though the cache store is memory.
    expect(
      await SharedPreferencesAsync().getString('configwire.dev.userId'),
      pinned,
    );
    await first.dispose();

    // Relaunch with a fresh Memory store reuses the fallback-persisted ID
    // without generating again — not anonymous.
    final second = ConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      store: MemoryCacheStore(),
    );
    await second.configureFlutter(
      collectDevice: false,
      idGenerator: () => throw StateError('must reuse persisted ID'),
    );
    expect(second.targeting.userId, pinned);
    expect(second.targeting.userId, isNotEmpty);
    await second.dispose();
  });

  test('(d) bare ConfigWire + configureFlutter persists under default key',
      () async {
    final cw = ConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
    );
    await cw.configureFlutter(collectDevice: false);
    expect(cw.targeting.userId, matches(simpleId));
    final pinned =
        await SharedPreferencesAsync().getString('configwire.dev.userId');
    expect(pinned, cw.targeting.userId);
    final stable = cw.targeting.userId;
    await cw.dispose();

    // Relaunch reuses the default-key ID without regenerating.
    final relaunch = ConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
    );
    await relaunch.configureFlutter(
      collectDevice: false,
      idGenerator: () => throw StateError('must reuse persisted ID'),
    );
    expect(relaunch.targeting.userId, stable);
    await relaunch.dispose();
  });
}
