// Suite for `ConfigWireFlutter.createConfigWire` (plan checkbox 7).
//
// Hermetic by construction: every case passes `ensureInitialized: false`
// (the default `true` performs a real forced fetch against `baseUrl`).
// The async prefs backend is seeded per test via
// `InMemorySharedPreferencesAsync` (Task-11 technique) so the factory's
// real `SharedPreferencesAsync()` construction never throws.
import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  void expectSameTargeting(Targeting actual, Targeting expected) {
    expect(actual.userId, expected.userId);
    expect(actual.platform, expected.platform);
    expect(actual.appVersion, expected.appVersion);
    expect(actual.locale, expected.locale);
    expect(actual.country, expected.country);
    expect(actual.customAttrs, expected.customAttrs);
  }

  test('explicitTargeting wins wholesale even with collectDevice: true',
      () async {
    const explicit = Targeting(
      userId: 'user-7',
      platform: 'ios',
      appVersion: '1.2.3',
      locale: 'en-US',
      country: 'US',
      customAttrs: {'plan': 'pro', 'device_model': 'custom'},
    );
    final cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      explicitTargeting: explicit,
      collectDevice: true,
      ensureInitialized: false,
    );
    expectSameTargeting(cw.targeting, explicit);
    await cw.dispose();
  });

  test('collectDevice: false with no explicit yields anonymous targeting',
      () async {
    final cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      collectDevice: false,
      ensureInitialized: false,
    );
    expectSameTargeting(cw.targeting, const Targeting());
    expect(cw.targeting.toQueryParameters(), isEmpty);
    await cw.dispose();
  });

  test('collectDevice: false keeps userId/customAttrs on anonymous base',
      () async {
    final cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      userId: 'user-7',
      customAttrs: const {'plan': 'pro'},
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, 'user-7');
    expect(cw.targeting.customAttrs, {'plan': 'pro'});
    expect(cw.targeting.platform, isEmpty);
    expect(cw.targeting.toQueryParameters()['uid'], 'user-7');
    await cw.dispose();
  });

  test('userId/customAttrs merge over auto-collected device targeting',
      () async {
    // Real collector in the test env: plugin seams degrade (no device),
    // so only the explicit-over-auto merge outcome is asserted — userId
    // and customAttrs come from the explicit input.
    final cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      userId: 'user-7',
      customAttrs: const {'plan': 'pro'},
      ensureInitialized: false,
    );
    expect(cw.targeting.userId, 'user-7');
    expect(cw.targeting.customAttrs['plan'], 'pro');
    await cw.dispose();
  });

  test('returned ConfigWire is usable: defaults fallback + version 0',
      () async {
    final cw = await ConfigWireFlutter.createConfigWire(
      apiKey: 'sk-test',
      env: 'dev',
      baseUrl: 'http://127.0.0.1:8090',
      defaults: const {'launch_flag': true, 'retries': 2},
      userId: 'user-7',
      collectDevice: false,
      ensureInitialized: false,
    );
    expect(cw.getBool('launch_flag'), isTrue);
    expect(cw.getInt('retries'), 2);
    expect(cw.getBool('missing_flag'), isNull);
    expect(cw.targeting.userId, 'user-7');
    expect(cw.version, 0);
    await cw.dispose();
  });
}
