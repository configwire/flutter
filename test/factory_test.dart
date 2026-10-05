// Suite for `ConfigWireFlutter.createConfigWire` with the new public API:
//
//   createConfigWire({
//     required apiKey, env, baseUrl, defaults,
//     String Function() idGenerator = defaultIdGenerator,
//     bool collectDevice = true,
//     String prefixCache = 'configwire',
//     ...
//   })
//
// Key scheme: `<prefixCache>.<encode(env)>.cache` for values,
// `<prefixCache>.<encode(env)>.userId` for the install ID.
// Identity: load-persisted, else `idGenerator()` supplies the first-run ID
// (then pinned); the generator never runs again once a value is stored.
//
// Hermetic by construction: every case passes `ensureInitialized: false`
// (the default `true` performs a real forced fetch against `baseUrl`).
// The async prefs backend is seeded per test via
// `InMemorySharedPreferencesAsync` so the factory's
// real `SharedPreferencesAsync()` construction never throws.
import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  // Simple-ID matcher shared by the install-ID cases.
  final simpleId = RegExp(r'^[a-z0-9]{15}$');

  test('collectDevice: false keeps install ID + customAttrs', () async {
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
    expect(cw.targeting.platform, isEmpty);
    expect(cw.targeting.toQueryParameters()['uid'], cw.targeting.userId);
    await cw.dispose();
  });

  test('install ID + customAttrs merge over auto-collected device', () async {
    // Real collector in the test env: plugin seams degrade (no device),
    // so only the merge outcome is asserted — the install ID survives
    // device collection and customAttrs pass through untouched.
    final cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      customAttrs: const {'plan': 'pro'},
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, matches(simpleId));
    expect(cw.targeting.customAttrs['plan'], 'pro');
    await cw.dispose();
  });

  test(
    'returned ConfigWire is usable: defaults fallback + version 0',
    () async {
      final cw = await ConfigWireFlutter.createConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        defaults: const {'launch_flag': true, 'retries': 2},
        collectDevice: false,
        ensureInitialized: false,
      );
      expect(cw.getBool('launch_flag'), isTrue);
      expect(cw.getInt('retries'), 2);
      expect(cw.getBool('missing_flag'), isNull);
      expect(cw.targeting.userId, matches(simpleId));
      expect(cw.version, 0);
      await cw.dispose();
    },
  );

  test(
    'default first launch generates a simple ID + persists; relaunch restores',
    () async {
      var cw = await ConfigWireFlutter.createConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        collectDevice: false,
        ensureInitialized: false,
      );
      expect(cw.targeting.userId, matches(simpleId));
      expect(cw.targeting.toQueryParameters()['uid'], cw.targeting.userId);
      final generated = cw.targeting.userId;
      // Persisted under the default key.
      expect(
        await loadPersistedUserId(prefs: SharedPreferencesAsync(), env: 'dev'),
        generated,
      );
      await cw.dispose();

      // Relaunch with no override restores the same generated ID.
      cw = await ConfigWireFlutter.createConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        collectDevice: false,
        ensureInitialized: false,
      );
      expect(cw.targeting.userId, generated);
      await cw.dispose();
    },
  );

  test('custom idGenerator supplies the first-run ID and is pinned', () async {
    var calls = 0;
    String generator() {
      calls++;
      return 'my-device-42';
    }

    var cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      idGenerator: generator,
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, 'my-device-42');
    expect(calls, 1);
    expect(
      await loadPersistedUserId(prefs: SharedPreferencesAsync(), env: 'dev'),
      'my-device-42',
    );
    await cw.dispose();

    // Relaunch without the generator restores the pinned value.
    cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, 'my-device-42');
    await cw.dispose();
  });

  test('idGenerator is not called when an ID is already persisted', () async {
    var calls = 0;
    String generator() {
      calls++;
      return 'should-never-be-used';
    }

    // Seed the persisted ID via a default first launch.
    var cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      collectDevice: false,
      ensureInitialized: false,
    );
    final installId = cw.targeting.userId;
    await cw.dispose();

    cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      idGenerator: generator,
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, installId);
    expect(calls, 0);
    await cw.dispose();
  });

  test('custom prefixCache isolates keys', () async {
    final cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      collectDevice: false,
      prefixCache: 'myapp',
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, matches(simpleId));
    await cw.dispose();

    final prefs = SharedPreferencesAsync();
    expect(await prefs.getString('myapp.dev.userId'), matches(simpleId));
    expect(await prefs.getString('configwire.dev.userId'), isNull);
    expect(await prefs.getString('myapp.dev.cache'), isNull);
    expect(await prefs.getString('configwire.dev.cache'), isNull);
  });

  test('idGenerator output is trimmed before persisting', () async {
    var cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      idGenerator: () => '  user-9  ',
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, 'user-9');
    expect(cw.targeting.toQueryParameters()['uid'], 'user-9');
    expect(
      await loadPersistedUserId(prefs: SharedPreferencesAsync(), env: 'dev'),
      'user-9',
    );
    await cw.dispose();

    // Relaunch reuses the pinned trimmed value without calling again.
    var calls = 0;
    cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      idGenerator: () {
        calls++;
        return 'unused';
      },
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, 'user-9');
    expect(calls, 0);
    await cw.dispose();
  });

  test(
    'idGenerator returning empty stays anonymous and pins nothing',
    () async {
      var cw = await ConfigWireFlutter.createConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        idGenerator: () => '',
        collectDevice: false,
        ensureInitialized: false,
      );
      expect(cw.targeting.userId, isEmpty);
      expect(cw.targeting.toQueryParameters(), isNot(contains('uid')));
      expect(
        await loadPersistedUserId(prefs: SharedPreferencesAsync(), env: 'dev'),
        isNull,
      );
      await cw.dispose();

      // Nothing pinned, so the next launch generates a fresh install ID.
      cw = await ConfigWireFlutter.createConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        collectDevice: false,
        ensureInitialized: false,
      );
      expect(cw.targeting.userId, matches(simpleId));
      await cw.dispose();
    },
  );

  test(
    'custom idGenerator under a custom prefix writes under that prefix',
    () async {
      final cw = await ConfigWireFlutter.createConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        idGenerator: () => 'user-9',
        prefixCache: 'myapp',
        ensureInitialized: false,
      );
      expect(cw.targeting.userId, 'user-9');
      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString('myapp.dev.userId'), 'user-9');
      expect(await prefs.getString('configwire.dev.userId'), isNull);
      await cw.dispose();
    },
  );

  test('generateUserId produces unique simple IDs', () {
    final seen = <String>{generateUserId(), generateUserId()};
    expect(seen, hasLength(2));
    for (final id in seen) {
      expect(id, matches(simpleId));
    }
  });
}
