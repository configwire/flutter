// ignore_for_file: deprecated_member_use
// Compat: Targeting.country is deprecated in client/dart until next major;
// read here to assert the stable install-ID wiring.
// Suite for the bring-your-own flow:
//
//   final cw = ConfigWire(..., store: SharedPreferencesCacheStore(env: env));
//   await cw.configureFlutter(...);
//
// Configuring never fetches by default (targeting only — hermetic, no
// network); with no server listening these cases only assert targeting
// and defaults. The async prefs backend is seeded per test via
// `InMemorySharedPreferencesAsync` so the `SharedPreferencesCacheStore`
// construction never throws.
import 'dart:math';
import 'dart:ui' show Locale;

import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// Fake locale source standing in for `PlatformDispatcher.instance`.
class FakeDispatcher implements DeviceLocaleDispatcher {
  FakeDispatcher(this.locale);
  @override
  final Locale locale;
}

/// Fake version source standing in for `PackageInfoPlatform.instance.getAll()`.
class FakePackageInfo implements AppVersionReader {
  FakePackageInfo(this.version);
  final String version;

  @override
  Future<String> fetchVersion() async => version;
}

/// Custom collector that always throws (never-throws contract probe).
class ThrowingCollector extends DeviceTargetingCollector {
  @override
  Future<Targeting> resolveDeviceTargeting(
    String userId,
    Map<String, Object?> customAttrs,
  ) async => throw StateError('collector exploded');
}

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

  test('generateUserId/defaultIdGenerator produce 15-char IDs', () {
    expect(generateUserId(), matches(RegExp(r'^[a-z0-9]{15}$')));
    expect(defaultIdGenerator(), matches(RegExp(r'^[a-z0-9]{15}$')));
    expect(generateUserId(Random(42)), generateUserId(Random(42)));
  });

  test('first launch generates and persists a 15-char install ID', () async {
    final cw = _testClient(defaults: const {'launch_flag': true});
    await cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
    );
    expect(cw.targeting.userId, matches(RegExp(r'^[a-z0-9]{15}$')));
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    expect(cw.getBool('launch_flag'), isTrue);
    final q = cw.targeting.toQueryParameters();
    expect(q.containsKey('uid'), isFalse);
    expect(q['userHash'], equals(sha256Hex16(cw.targeting.userId)));
    expect(q['userHash'], matches(RegExp(r'^[0-9a-f]{16}$')));
    final pinned = await SharedPreferencesAsync().getString(
      'configwire.dev.userId',
    );
    expect(pinned, cw.targeting.userId);
    await cw.dispose();
  });

  test('persisted ID readable via store.prefs user_store helpers', () async {
    final store = SharedPreferencesCacheStore(env: 'dev');
    final cw = ConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      store: store,
    );
    await cw.configureFlutter(
      collectDevice: false,
      idGenerator: () => 'abc123def456ghi',
    );
    expect(cw.targeting.userId, 'abc123def456ghi');
    expect(
      await loadPersistedUserId(prefs: store.prefs, env: 'dev'),
      'abc123def456ghi',
    );
    await cw.dispose();
  });

  test('relaunch restores the SAME install ID without regenerating', () async {
    var calls = 0;
    String generator() {
      calls++;
      return 'abc123def456ghi';
    }

    final first = _testClient();
    await first.configureFlutter(collectDevice: false, idGenerator: generator);
    expect(first.targeting.userId, 'abc123def456ghi');
    expect(calls, 1);
    await first.dispose();

    final second = _testClient();
    await second.configureFlutter(collectDevice: false, idGenerator: generator);
    expect(second.targeting.userId, 'abc123def456ghi');
    expect(
      calls,
      1,
      reason: 'persisted ID must be reused, generator not called again',
    );
    await second.dispose();
  });

  test('custom idGenerator is pinned and persisted', () async {
    final cw = _testClient();
    await cw.configureFlutter(
      collectDevice: false,
      idGenerator: () => 'customid1234567',
    );
    expect(cw.targeting.userId, 'customid1234567');
    final pinned = await SharedPreferencesAsync().getString(
      'configwire.dev.userId',
    );
    expect(pinned, 'customid1234567');
    await cw.dispose();
  });

  test(
    'idGenerator output is trimmed before persisting + emits userHash',
    () async {
      final cw = _testClient();
      await cw.configureFlutter(
        collectDevice: false,
        idGenerator: () => '  user-9  ',
      );
      expect(cw.targeting.userId, 'user-9');
      final trimQ = cw.targeting.toQueryParameters();
      expect(trimQ.containsKey('uid'), isFalse);
      expect(trimQ['userHash'], equals(sha256Hex16('user-9')));
      expect(
        await loadPersistedUserId(prefs: SharedPreferencesAsync(), env: 'dev'),
        'user-9',
      );
      await cw.dispose();

      // Relaunch reuses the pinned trimmed value without calling again.
      var calls = 0;
      final relaunch = _testClient();
      await relaunch.configureFlutter(
        collectDevice: false,
        idGenerator: () {
          calls++;
          return 'unused';
        },
      );
      expect(relaunch.targeting.userId, 'user-9');
      expect(calls, 0);
      await relaunch.dispose();
    },
  );

  test('empty-generator output stays anonymous and pins nothing', () async {
    final cw = _testClient();
    await cw.configureFlutter(collectDevice: false, idGenerator: () => '');
    expect(cw.targeting.userId, isEmpty);
    final anonQ = cw.targeting.toQueryParameters();
    expect(anonQ.containsKey('uid'), isFalse);
    expect(anonQ, isNot(contains('userHash')));
    final pinned = await SharedPreferencesAsync().getString(
      'configwire.dev.userId',
    );
    expect(pinned, isNull);
    await cw.dispose();
  });

  test('throwing idGenerator degrades to anonymous and pins nothing', () async {
    final cw = _testClient();
    await cw.configureFlutter(
      collectDevice: false,
      idGenerator: () => throw StateError('no entropy'),
    );
    expect(cw.targeting.userId, isEmpty);
    final pinned = await SharedPreferencesAsync().getString(
      'configwire.dev.userId',
    );
    expect(pinned, isNull);
    await cw.dispose();
  });

  test('custom memory store keeps a stable ID via prefs fallback', () async {
    final cw = ConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      store: MemoryCacheStore(),
    );
    await cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
    );
    // Backward compat with 0.2.x: the install ID persists via the prefs
    // fallback even though the cache store is memory (never anonymous
    // while prefs are writable).
    expect(cw.targeting.userId, matches(RegExp(r'^[a-z0-9]{15}$')));
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    expect(
      await SharedPreferencesAsync().getString('configwire.dev.userId'),
      cw.targeting.userId,
    );
    await cw.dispose();
  });

  test(
    'bare ConfigWire gets a default prefs store with stable install ID',
    () async {
      final cw = ConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
      );
      await cw.configureFlutter(collectDevice: false);
      expect(cw.store is SharedPreferencesCacheStore, isTrue);
      expect(cw.targeting.userId, matches(RegExp(r'^[a-z0-9]{15}$')));
      final pinned = await SharedPreferencesAsync().getString(
        'configwire.dev.userId',
      );
      expect(pinned, cw.targeting.userId);
      await cw.dispose();
    },
  );

  test('legacy-seeded configwire.dev.userId is adopted verbatim', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'configwire.dev.userId': 'legacyseed12345',
        });
    final cw = _testClient();
    await cw.configureFlutter(
      collectDevice: false,
      idGenerator: () => throw StateError('must not generate'),
    );
    expect(cw.targeting.userId, 'legacyseed12345');
    await cw.dispose();
  });

  test('throwing collector degrades to ID-only targeting', () async {
    final cw = _testClient();
    await cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collector: ThrowingCollector(),
      idGenerator: () => 'abc123def456ghi',
    );
    expect(cw.targeting.userId, 'abc123def456ghi');
    expect(cw.targeting.platform, isEmpty);
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });

  test('configureFlutter is idempotent across repeated calls', () async {
    final cw = _testClient();
    await cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
      idGenerator: () => 'abc123def456ghi',
    );
    final firstId = cw.targeting.userId;
    await cw.configureFlutter(ensureInitialized: false);
    expect(cw.targeting.userId, firstId);
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });

  test('concurrent configureFlutter calls join a single init', () async {
    final cw = _testClient();
    Future<void> init() => cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
      idGenerator: () => 'abc123def456ghi',
    );
    await Future.wait([init(), init()]);
    expect(cw.targeting.userId, 'abc123def456ghi');
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });

  test('collectDevice merges device fields with the install ID', () async {
    final cw = _testClient();
    await cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      idGenerator: () => 'abc123def456ghi',
      collector: DeviceTargetingCollector(
        platform: TargetPlatform.android,
        isWeb: false,
        packageInfo: FakePackageInfo('1.0.0+1'),
        dispatcher: FakeDispatcher(const Locale('en', 'US')),
      ),
    );
    expect(cw.targeting.userId, 'abc123def456ghi');
    expect(cw.targeting.platform, 'android');
    expect(cw.targeting.appVersion, '1.0.0');
    expect(cw.targeting.locale, 'en-US');
    expect(cw.targeting.country, 'US');
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });

  test('store param upgrades a ConfigWire built without one', () async {
    final cw = ConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
    );
    await cw.configureFlutter(
      collectDevice: false,
      store: SharedPreferencesCacheStore(env: 'dev'),
      idGenerator: () => 'abc123def456ghi',
    );
    expect(cw.targeting.userId, 'abc123def456ghi');
    await cw.dispose();
  });
}
