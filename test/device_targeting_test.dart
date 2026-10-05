// Suite for the device targeting collector (`lib/src/device_targeting.dart`).
//
// Contract under test (from `client/dart/lib/src/targeting.dart` and
// `lib/src/device_targeting.dart`):
// * Injectable `DeviceTargetingCollector({dispatcher?, packageInfo?})` +
//   `resolveDeviceTargeting()` returning `Targeting`.
// * Merge rule: explicit non-empty scalars win per-field;
//   `customAttrs` comes from the explicit input.
// * Normalization: platform in {android, ios, web, macos, windows, linux}
//   from `defaultTargetPlatform` with a `kIsWeb` guard (no `dart:io` on the
//   Web path); `appVersion` strips `+build`; locale via `toLanguageTag`;
//   country from `locale.countryCode`, empty unless present or explicit.
// * Never-throws rule (single rule for this suite): platform is
//   param-derived, NOT plugin-derived, so it ALWAYS survives seam
//   failures. When every seam throws, the result is platform-only
//   (version/locale/country empty, customAttrs empty) — never fully
//   anonymous, never a throw.
// * No extra keys: no collector output key exists beyond
//   platform/appVersion/locale/country; `customAttrs` comes from the
//   explicit input.
//
// Fakes below are hand-written classes implementing the collector's seam
// types. They NEVER touch real `PackageInfo.fromPlatform()` — no device
// exists in CI.
import 'dart:ui' show Locale;

import 'package:configwire/configwire.dart';
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
      };
      for (final entry in expected.entries) {
        final targeting = await collector(platform: entry.key)
            .resolveDeviceTargeting();
        expect(targeting.platform, entry.value,
            reason: 'platform ${entry.key}');
      }
    });

    test('isWeb forces web regardless of the host platform', () async {
      for (final platform in TargetPlatform.values) {
        final targeting = await collector(platform: platform, isWeb: true)
            .resolveDeviceTargeting();
        expect(targeting.platform, 'web',
            reason: 'platform $platform with isWeb=true');
      }
    });

    test('unmapped platforms degrade to empty (omitted from query)',
        () async {
      final targeting = await collector(platform: TargetPlatform.fuchsia)
          .resolveDeviceTargeting();
      expect(targeting.platform, isEmpty);
      expect(targeting.toQueryParameters(), isNot(contains('platform')));
    });
  });

  group('appVersion normalization', () {
    test('strips +build metadata (1.0.0+1 -> 1.0.0)', () async {
      final targeting = await collector(
        packageInfo: FakePackageInfo('1.0.0+1'),
      ).resolveDeviceTargeting();
      expect(targeting.appVersion, '1.0.0');
    });

    test('strips dotted build metadata (2.3.4+build.5 -> 2.3.4)', () async {
      final targeting = await collector(
        packageInfo: FakePackageInfo('2.3.4+build.5'),
      ).resolveDeviceTargeting();
      expect(targeting.appVersion, '2.3.4');
    });

    test('leaves a bare semver version untouched', () async {
      final targeting = await collector(
        packageInfo: FakePackageInfo('1.2.3'),
      ).resolveDeviceTargeting();
      expect(targeting.appVersion, '1.2.3');
    });

    test('server can strict-semver-compare the normalized version',
        () async {
      final targeting = await collector(
        packageInfo: FakePackageInfo('1.0.0+1'),
      ).resolveDeviceTargeting();
      // Must be parseable MAJOR.MINOR.PATCH: no '+' may survive.
      expect(targeting.appVersion, isNot(contains('+')));
      expect(targeting.toQueryParameters()['appVersion'], '1.0.0');
    });
  });

  group('locale + country normalization', () {
    test('locale uses toLanguageTag (en_US -> en-US)', () async {
      final targeting = await collector(
        dispatcher: FakeDispatcher(const Locale('en', 'US')),
      ).resolveDeviceTargeting();
      expect(targeting.locale, 'en-US');
    });

    test('country comes from locale.countryCode', () async {
      final targeting = await collector(
        dispatcher: FakeDispatcher(const Locale('en', 'US')),
      ).resolveDeviceTargeting();
      expect(targeting.country, 'US');
    });

    test('locale without a country leaves country empty', () async {
      final targeting = await collector(
        dispatcher: FakeDispatcher(const Locale('fr')),
      ).resolveDeviceTargeting();
      expect(targeting.locale, 'fr');
      expect(targeting.country, isEmpty);
      expect(targeting.toQueryParameters(), isNot(contains('country')));
    });
  });

  group('customAttrs from explicit input', () {
    test('no explicit targeting yields empty customAttrs', () async {
      final targeting = await collector().resolveDeviceTargeting();
      expect(targeting.customAttrs, isEmpty);
      expect(targeting.toQueryParameters(), isNot(contains('attrs')));
    });

    test('explicit customAttrs survive untouched', () async {
      final targeting = await collector().resolveDeviceTargeting(
        explicit: const Targeting(
          customAttrs: {'plan': 'pro'},
        ),
      );
      // Exact equality: no auto keys may be added.
      expect(targeting.customAttrs, {'plan': 'pro'});
    });

    test('explicit customAttrs are copied, never enriched', () async {
      final targeting = await collector(
        platform: TargetPlatform.iOS,
      ).resolveDeviceTargeting(
        explicit: const Targeting(
          customAttrs: {'plan': 'pro', 'seats': 5},
        ),
      );
      expect(targeting.customAttrs, {'plan': 'pro', 'seats': 5});
      expect(targeting.toQueryParameters()['attrs'], contains('pro'));
    });
  });

  group('explicit-over-auto merge contract', () {
    test('explicit Targeting fields win per-field', () async {
      final targeting = await collector().resolveDeviceTargeting(
        explicit: const Targeting(
          userId: 'user-7',
          platform: 'ios',
          appVersion: '9.9.9',
          locale: 'fr-FR',
          country: 'FR',
        ),
      );
      expect(targeting.userId, 'user-7');
      expect(targeting.platform, 'ios');
      expect(targeting.appVersion, '9.9.9');
      expect(targeting.locale, 'fr-FR');
      expect(targeting.country, 'FR');
    });

    test('empty explicit fields keep the auto-collected values', () async {
      final targeting = await collector().resolveDeviceTargeting(
        explicit: const Targeting(platform: 'ios'),
      );
      // Only platform was explicit; the rest stays auto-collected.
      expect(targeting.platform, 'ios');
      expect(targeting.appVersion, '1.0.0');
      expect(targeting.locale, 'en-US');
      expect(targeting.country, 'US');
    });

    test('explicit country wins when the locale has none', () async {
      final targeting = await collector(
        dispatcher: FakeDispatcher(const Locale('fr')),
      ).resolveDeviceTargeting(
        explicit: const Targeting(country: 'CA'),
      );
      expect(targeting.locale, 'fr');
      expect(targeting.country, 'CA');
    });
  });

  group('never throws (plugin errors degrade per-field)', () {
    test('all seams throwing keeps param-derived platform, no throw',
        () async {
      final c = collector(
        packageInfo: ThrowingPackageInfo(),
        dispatcher: ThrowingDispatcher(),
      );
      await expectLater(c.resolveDeviceTargeting(), completes);
      final targeting = await c.resolveDeviceTargeting();
      // Platform is param-derived, so it survives; every plugin-derived
      // field degrades to empty.
      expect(targeting.userId, isEmpty);
      expect(targeting.platform, 'android');
      expect(targeting.appVersion, isEmpty);
      expect(targeting.locale, isEmpty);
      expect(targeting.country, isEmpty);
      expect(targeting.customAttrs, isEmpty);
    });

    test('package-info failure alone keeps platform/locale/country',
        () async {
      final targeting = await collector(
        packageInfo: ThrowingPackageInfo(),
      ).resolveDeviceTargeting();
      expect(targeting.platform, 'android');
      expect(targeting.appVersion, isEmpty);
      expect(targeting.locale, 'en-US');
      expect(targeting.country, 'US');
      expect(targeting.customAttrs, isEmpty);
    });

    test('dispatcher failure alone keeps platform/version', () async {
      final targeting = await collector(
        dispatcher: ThrowingDispatcher(),
      ).resolveDeviceTargeting();
      expect(targeting.platform, 'android');
      expect(targeting.appVersion, '1.0.0');
      expect(targeting.locale, isEmpty);
      expect(targeting.country, isEmpty);
      expect(targeting.customAttrs, isEmpty);
    });
  });
}
