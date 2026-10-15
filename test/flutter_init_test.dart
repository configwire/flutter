// Suite for the bring-your-own flow:
//
//   final cw = ConfigWire(..., store: SharedPreferencesCacheStore(env: env));
//   await cw.configureFlutter(...);
//
// Configuring never fetches by default (targeting only — hermetic, no
// network); with no server listening these cases only assert targeting,
// persistence, and defaults. The async prefs backend is seeded per test via
// `InMemorySharedPreferencesAsync` so the default
// `SharedPreferencesAsync()` construction never throws.
import 'dart:ui' show Locale;

import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
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
  ) async =>
      throw StateError('collector exploded');
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

  final simpleId = RegExp(r'^[a-z0-9]{15}$');

  test('configureFlutter resolves install ID and customAttrs', () async {
    final cw = _testClient(defaults: const {'launch_flag': true});
    await cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
    );
    expect(cw.targeting.userId, matches(simpleId));
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    expect(cw.getBool('launch_flag'), isTrue);
    await cw.dispose();
  });

  test('configureFlutter is idempotent: idGenerator runs once', () async {
    var calls = 0;
    final cw = _testClient();
    await cw.configureFlutter(
      idGenerator: () {
        calls++;
        return 'pinned-1';
      },
      collectDevice: false,
    );
    await cw.configureFlutter(ensureInitialized: false);
    expect(cw.targeting.userId, 'pinned-1');
    expect(calls, 1);
    await cw.dispose();
  });

  test('concurrent configureFlutter calls join a single init', () async {
    var calls = 0;
    final cw = _testClient();
    Future<void> init() => cw.configureFlutter(
      idGenerator: () {
        calls++;
        return 'concurrent-1';
      },
      collectDevice: false,
    );
    await Future.wait([init(), init()]);
    expect(cw.targeting.userId, 'concurrent-1');
    expect(calls, 1);
    await cw.dispose();
  });

  test('custom idGenerator pins and persists across instances', () async {
    var cw = _testClient();
    await cw.configureFlutter(
      idGenerator: () => 'my-device-42',
      collectDevice: false,
    );
    expect(cw.targeting.userId, 'my-device-42');
    await cw.dispose();

    cw = _testClient();
    await cw.configureFlutter(
      collectDevice: false,
    );
    expect(cw.targeting.userId, 'my-device-42');
    await cw.dispose();
  });

  test('collectDevice merges install ID with device fields', () async {
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
    expect(cw.targeting.userId, matches(simpleId));
    expect(cw.targeting.platform, 'android');
    expect(cw.targeting.appVersion, '1.0.0');
    expect(cw.targeting.locale, 'en-US');
    expect(cw.targeting.country, 'US');
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });

  test('throwing custom collector degrades to identity-only', () async {
    final cw = _testClient();
    await cw.configureFlutter(
      customAttrs: const {'plan': 'pro'},
      collector: ThrowingCollector(),
    );
    expect(cw.targeting.userId, matches(simpleId));
    expect(cw.targeting.platform, isEmpty);
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    await cw.dispose();
  });
}
