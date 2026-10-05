// Suite for the device targeting collector (`lib/src/device_targeting.dart`).
//
// Contract under test (from `client/dart/lib/src/targeting.dart` and
// `lib/src/device_targeting.dart`):
// * Injectable `DeviceTargetingCollector({dispatcher?, packageInfo?})` +
//   `resolveDeviceTargeting(userId, customAttrs)` returning `Targeting`.
// * Passthrough: `userId` and `customAttrs` are used untouched (a defensive
//   copy for the map); no device keys are ever added to `customAttrs`.
// * Normalization: platform in {android, ios, web, macos, windows, linux}
//   from `defaultTargetPlatform` with a `kIsWeb` guard (no `dart:io` on the
//   Web path); `appVersion` strips `+build`; locale via `toLanguageTag`;
//   country from `locale.countryCode`, empty unless present.
// * Never-throws rule (single rule for this suite): platform is
//   param-derived, NOT plugin-derived, so it ALWAYS survives seam
//   failures. When every seam throws, the result is platform + the
//   caller-supplied `userId`/`customAttrs` (version/locale/country empty)
//   — never a throw.
// * No extra keys: no collector output key exists beyond
//   platform/appVersion/locale/country; `customAttrs` comes from the
//   caller input alone.
//
// Fakes below are hand-written classes implementing the collector's seam
// types. They NEVER touch real `PackageInfo.fromPlatform()` — no device
// exists in CI.
import 'dart:ui' show Locale;

import 'package:configwire_flutter/src/device_targeting.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Fakes for the collector's injectable seams.
// ---------------------------------------------------------------------------

/// Fake locale source standing in for `PlatformDispatcher.instance`.
class FakeDispatcher implements DeviceLocaleDispatcher {
  FakeDispatcher(this._locale);
  final Locale _locale;

  @override
  Locale get locale => _locale;
}

/// Fake version source standing in for `PackageInfo.fromPlatform()`.
class FakePackageInfo implements AppVersionReader {
  FakePackageInfo(this._version);
  final String _version;

  @override
  Future<String> fetchVersion() async => _version;
}

/// Version seam that always throws (plugin failure simulation).
class ThrowingPackageInfo implements AppVersionReader {
  @override
  Future<String> fetchVersion() async =>
      throw StateError('PackageInfo.fromPlatform failed');
}

/// Locale seam that always throws (dispatcher failure simulation).
class ThrowingDispatcher implements DeviceLocaleDispatcher {
  @override
  Locale get locale => throw StateError('dispatcher unavailable');
}

/// Builds a collector with deterministic fakes; tests override per case.
///
/// `platform`/`isWeb` stand in for `defaultTargetPlatform`/`kIsWeb` so
/// tests stay hermetic (no global `debugDefaultTargetPlatformOverride`).
DeviceTargetingCollector collector({
  TargetPlatform platform = TargetPlatform.android,
  bool isWeb = false,
  AppVersionReader? packageInfo,
  DeviceLocaleDispatcher? dispatcher,
}) {
  return DeviceTargetingCollector(
    platform: platform,
    isWeb: isWeb,
    packageInfo: packageInfo ?? FakePackageInfo('1.0.0+1'),
    dispatcher: dispatcher ?? FakeDispatcher(const Locale('en', 'US')),
  );
}

void main() {
  group('platform normalization', () {
    test('maps every TargetPlatform to the server platform vocabulary',
        () async {
      const expected = {
        TargetPlatform.android: 'android',
        TargetPlatform.iOS: 'ios',
        TargetPlatform.macOS: 'macos',
        TargetPlatform.windows: 'windows',
        TargetPlatform.linux: 'linux',
        TargetPlatform.fuchsia: 'fuchsia',
      };
      for (final entry in expected.entries) {
        final targeting = await collector(platform: entry.key)
            .resolveDeviceTargeting('', {});
        expect(targeting.platform, entry.value,
            reason: 'platform ${entry.key}');
      }
    });

    test('isWeb forces web regardless of the host platform', () async {
      for (final platform in TargetPlatform.values) {
        final targeting = await collector(platform: platform, isWeb: true)
            .resolveDeviceTargeting('', {});
        expect(targeting.platform, 'web',
            reason: 'platform $platform with isWeb=true');
      }
    });

    test('fuchsia is covered and sent as a platform value', () async {
      final targeting = await collector(platform: TargetPlatform.fuchsia)
          .resolveDeviceTargeting('', {});
      expect(targeting.platform, 'fuchsia');
      expect(targeting.toQueryParameters()['platform'], 'fuchsia');
    });
  });

  group('appVersion normalization', () {
    test('strips +build metadata (1.0.0+1 -> 1.0.0)', () async {
      final targeting = await collector(
        packageInfo: FakePackageInfo('1.0.0+1'),
      ).resolveDeviceTargeting('', {});
      expect(targeting.appVersion, '1.0.0');
    });

    test('strips dotted build metadata (2.3.4+build.5 -> 2.3.4)', () async {
      final targeting = await collector(
        packageInfo: FakePackageInfo('2.3.4+build.5'),
      ).resolveDeviceTargeting('', {});
      expect(targeting.appVersion, '2.3.4');
    });

    test('leaves a bare semver version untouched', () async {
      final targeting = await collector(
        packageInfo: FakePackageInfo('1.2.3'),
      ).resolveDeviceTargeting('', {});
      expect(targeting.appVersion, '1.2.3');
    });

    test('server can strict-semver-compare the normalized version',
        () async {
      final targeting = await collector(
        packageInfo: FakePackageInfo('1.0.0+1'),
      ).resolveDeviceTargeting('', {});
      // Must be parseable MAJOR.MINOR.PATCH: no '+' may survive.
      expect(targeting.appVersion, isNot(contains('+')));
      expect(targeting.toQueryParameters()['appVersion'], '1.0.0');
    });
  });

  group('locale + country normalization', () {
    test('locale uses toLanguageTag (en_US -> en-US)', () async {
      final targeting = await collector(
        dispatcher: FakeDispatcher(const Locale('en', 'US')),
      ).resolveDeviceTargeting('', {});
      expect(targeting.locale, 'en-US');
    });

    test('country comes from locale.countryCode', () async {
      final targeting = await collector(
        dispatcher: FakeDispatcher(const Locale('en', 'US')),
      ).resolveDeviceTargeting('', {});
      expect(targeting.country, 'US');
    });

    test('locale without a country leaves country empty', () async {
      final targeting = await collector(
        dispatcher: FakeDispatcher(const Locale('fr')),
      ).resolveDeviceTargeting('', {});
      expect(targeting.locale, 'fr');
      expect(targeting.country, isEmpty);
      expect(targeting.toQueryParameters(), isNot(contains('country')));
    });
  });

  group('userId + customAttrs passthrough', () {
    test('empty inputs yield empty identity fields', () async {
      final targeting = await collector().resolveDeviceTargeting('', {});
      expect(targeting.userId, isEmpty);
      expect(targeting.customAttrs, isEmpty);
      expect(
        targeting.toQueryParameters(),
        isNot(anyOf([contains('uid'), contains('attrs')])),
      );
    });

    test('userId passes through untouched', () async {
      final targeting = await collector().resolveDeviceTargeting(
        'user-7',
        {},
      );
      expect(targeting.userId, 'user-7');
      expect(targeting.toQueryParameters()['uid'], 'user-7');
    });

    test('customAttrs survive untouched', () async {
      final targeting = await collector().resolveDeviceTargeting(
        '',
        {'plan': 'pro'},
      );
      // Exact equality: no auto keys may be added.
      expect(targeting.customAttrs, {'plan': 'pro'});
    });

    test('customAttrs are copied, never enriched', () async {
      final targeting = await collector(
        platform: TargetPlatform.iOS,
      ).resolveDeviceTargeting(
        '',
        {'plan': 'pro', 'seats': 5},
      );
      expect(targeting.customAttrs, {'plan': 'pro', 'seats': 5});
      expect(targeting.toQueryParameters()['attrs'], contains('pro'));
    });

    test('identity rides alongside auto-collected device fields', () async {
      final targeting = await collector().resolveDeviceTargeting(
        'user-7',
        {'plan': 'pro'},
      );
      expect(targeting.userId, 'user-7');
      expect(targeting.customAttrs, {'plan': 'pro'});
      expect(targeting.platform, 'android');
      expect(targeting.appVersion, '1.0.0');
      expect(targeting.locale, 'en-US');
      expect(targeting.country, 'US');
    });
  });

  group('never throws (plugin errors degrade per-field)', () {
    test('all seams throwing keeps platform + identity, no throw', () async {
      final c = collector(
        packageInfo: ThrowingPackageInfo(),
        dispatcher: ThrowingDispatcher(),
      );
      await expectLater(
        c.resolveDeviceTargeting('user-7', {'plan': 'pro'}),
        completes,
      );
      final targeting = await c.resolveDeviceTargeting(
        'user-7',
        {'plan': 'pro'},
      );
      // Platform is param-derived, so it survives; every plugin-derived
      // field degrades to empty while the caller identity is preserved.
      expect(targeting.userId, 'user-7');
      expect(targeting.platform, 'android');
      expect(targeting.appVersion, isEmpty);
      expect(targeting.locale, isEmpty);
      expect(targeting.country, isEmpty);
      expect(targeting.customAttrs, {'plan': 'pro'});
    });

    test('package-info failure alone keeps platform/locale/country', () async {
      final targeting = await collector(
        packageInfo: ThrowingPackageInfo(),
      ).resolveDeviceTargeting('user-7', {});
      expect(targeting.userId, 'user-7');
      expect(targeting.platform, 'android');
      expect(targeting.appVersion, isEmpty);
      expect(targeting.locale, 'en-US');
      expect(targeting.country, 'US');
      expect(targeting.customAttrs, isEmpty);
    });

    test('dispatcher failure alone keeps platform/version', () async {
      final targeting = await collector(
        dispatcher: ThrowingDispatcher(),
      ).resolveDeviceTargeting('user-7', {});
      expect(targeting.userId, 'user-7');
      expect(targeting.platform, 'android');
      expect(targeting.appVersion, '1.0.0');
      expect(targeting.locale, isEmpty);
      expect(targeting.country, isEmpty);
      expect(targeting.customAttrs, isEmpty);
    });
  });
}
