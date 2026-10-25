// ignore_for_file: deprecated_member_use
// Compat: Targeting.country is deprecated in client/dart until next major;
// read here to assert device wiring. Targeting is always anonymous: no
// install ID is generated, persisted, or emitted; bucketing rides `?b=`.
// Suite for the bring-your-own flow:
//
//   final cw = ConfigWire(..., store: SharedPreferencesCacheStore(env: env));
//   await cw.configureFlutter(...);
//
// Configuring never fetches by default (targeting only — hermetic, no
// network); with no server listening these cases only assert targeting
// and defaults. The async prefs backend is seeded per test via
// `InMemorySharedPreferencesAsync` so the `SharedPreferencesCacheStore`
// construction never throws. Targeting is always anonymous: no install ID
// is generated, persisted, or emitted; bucketing rides the stable `?b=`.
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

  test('first launch resolves anonymous targeting with customAttrs', () async {
    final cw = _testClient(defaults: const {'launch_flag': true});
    await cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
    );
    // Targeting carries no identity: anonymous by construction.
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    expect(cw.getBool('launch_flag'), isTrue);
    final q = cw.targeting.toQueryParameters();
    expect(q.containsKey('uid'), isFalse);
    expect(q, isNot(contains('userHash')));
    await cw.dispose();
  });

  test('store-backed client resolves anonymous targeting', () async {
    final store = SharedPreferencesCacheStore(env: 'dev');
    final cw = ConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      store: store,
    );
    await cw.configureFlutter(collectDevice: false);
    // Anonymous even with a store-owned prefs backend beneath.
    expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
    expect(store.prefs, isA<SharedPreferencesAsync>());
    await cw.dispose();
  });

  test('relaunch resolves identically with no persisted identity', () async {
    final first = _testClient();
    await first.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
    );
    expect(first.targeting.customAttrs, {'plan': 'pro'});
    await first.dispose();

    final second = _testClient();
    await second.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
    );
    expect(second.targeting.customAttrs, {'plan': 'pro'});
    await second.dispose();
  });

  test('collectDevice false leaves device fields empty', () async {
    final cw = _testClient();
    await cw.configureFlutter(collectDevice: false);
    expect(cw.targeting.platform, isEmpty);
    expect(cw.targeting.customAttrs, isEmpty);
    final q = cw.targeting.toQueryParameters();
    expect(q.containsKey('uid'), isFalse);
    expect(q, isNot(contains('userHash')));
    await cw.dispose();
  });

  test('custom memory store configures anonymously', () async {
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
    // No identity persisted anywhere, nothing emitted.
    expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });

  test('bare ConfigWire gets a default prefs store', () async {
    final cw = ConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
    );
    await cw.configureFlutter(collectDevice: false);
    expect(cw.store is SharedPreferencesCacheStore, isTrue);
    expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
    await cw.dispose();
  });

  test('throwing collector degrades to customAttrs-only targeting', () async {
    final cw = _testClient();
    await cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collector: ThrowingCollector(),
    );
    expect(cw.targeting.platform, isEmpty);
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
    await cw.dispose();
  });

  test('configureFlutter is idempotent across repeated calls', () async {
    final cw = _testClient();
    await cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
    );
    await cw.configureFlutter(ensureInitialized: false);
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });

  test('concurrent configureFlutter calls join a single init', () async {
    final cw = _testClient();
    Future<void> init() => cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
    );
    await Future.wait([init(), init()]);
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });

  test(
    'collectDevice merges device fields while identity stays anonymous',
    () async {
      final cw = _testClient();
      await cw.configureFlutter(
        customAttrs: const {'plan': 'pro'},
        collector: DeviceTargetingCollector(
          platform: TargetPlatform.android,
          isWeb: false,
          packageInfo: FakePackageInfo('1.0.0+1'),
          dispatcher: FakeDispatcher(const Locale('en', 'US')),
        ),
      );
      expect(cw.targeting.platform, 'android');
      expect(cw.targeting.appVersion, '1.0.0');
      expect(cw.targeting.locale, 'en-US');
      expect(cw.targeting.country, 'US');
      expect(cw.targeting.customAttrs, {'plan': 'pro'});
      expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
      await cw.dispose();
    },
  );

  test('store param upgrades a ConfigWire built without one', () async {
    final cw = ConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
    );
    await cw.configureFlutter(
      collectDevice: false,
      store: SharedPreferencesCacheStore(env: 'dev'),
    );
    expect(cw.store is SharedPreferencesCacheStore, isTrue);
    await cw.dispose();
  });
}
