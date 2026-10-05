import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:configwire/configwire.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

/// Injectable seam for the device locale source.
///
/// Defaults to [PlatformDispatcher.instance] ([_PlatformDispatcherLocale]).
/// Tests inject a fake; no device exists in CI.
abstract class DeviceLocaleDispatcher {
  Locale get locale;
}

/// Injectable seam for the app-version source.
///
/// Defaults to [PackageInfo.fromPlatform] ([_PackageInfoVersionReader]).
/// Tests inject a fake; no device exists in CI.
abstract class AppVersionReader {
  Future<String> fetchVersion();
}

/// Real [DeviceLocaleDispatcher] over [PlatformDispatcher.instance].
///
/// The read stays lazy (inside [resolveDeviceTargeting], never in the
/// collector ctor) so construction never throws.
class _PlatformDispatcherLocale implements DeviceLocaleDispatcher {
  @override
  Locale get locale => PlatformDispatcher.instance.locale;
}

/// Real [AppVersionReader] over [PackageInfo.fromPlatform].
///
/// Failure degrades to `''` (omitted from the query) instead of throwing.
class _PackageInfoVersionReader implements AppVersionReader {
  @override
  Future<String> fetchVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '';
    }
  }
}

/// Collects device-derived [Targeting] for fetch query params.
///
/// * Platform comes from [platform] (default [defaultTargetPlatform])
///   with [isWeb] (default [kIsWeb]) forcing `web`. No `dart:io`
///   anywhere, so the Web build compiles.
/// * `appVersion` strips `+build` metadata for strict-semver compare.
/// * Locale via [Locale.toLanguageTag]; country from `countryCode`.
/// * [userId] and [customAttrs] pass through untouched (a defensive copy
///   for the map); no device keys are ever added to `customAttrs`.
/// * Never throws: each seam failure degrades its field; the outer
///   try/catch returns the [userId]-only targeting as a last resort.
///   Platform is param-derived (not plugin-derived), so it always
///   survives seam failures — only the plugin-derived fields
///   (appVersion/locale/country) degrade to empty.
class DeviceTargetingCollector {
  DeviceTargetingCollector({
    TargetPlatform? platform,
    bool? isWeb,
    DeviceLocaleDispatcher? dispatcher,
    AppVersionReader? packageInfo,
  }) : _platform = platform ?? defaultTargetPlatform,
       _isWeb = isWeb ?? kIsWeb,
       _dispatcher = dispatcher ?? _PlatformDispatcherLocale(),
       _packageInfo = packageInfo ?? _PackageInfoVersionReader();

  final TargetPlatform _platform;
  final bool _isWeb;
  final DeviceLocaleDispatcher _dispatcher;
  final AppVersionReader _packageInfo;

  static String _normalizePlatform(TargetPlatform platform, bool isWeb) {
    if (isWeb) return 'web';
    return platform.name.toLowerCase();
  }

  Future<Targeting> resolveDeviceTargeting(
    String userId,
    Map<String, Object?> customAttrs,
  ) async {
    try {
      final autoPlatform = _normalizePlatform(_platform, _isWeb);

      // appVersion: strip +build metadata (server strict-semver-compares).
      var autoVersion = '';
      try {
        autoVersion = (await _packageInfo.fetchVersion()).split('+').first;
      } catch (_) {
        autoVersion = '';
      }

      // locale + country.
      var autoLocale = '';
      var autoCountry = '';
      try {
        final locale = _dispatcher.locale;
        autoLocale = locale.toLanguageTag();
        autoCountry = locale.countryCode ?? '';
      } catch (_) {
        autoLocale = '';
        autoCountry = '';
      }

      return Targeting(
        userId: userId,
        platform: autoPlatform,
        appVersion: autoVersion,
        locale: autoLocale,
        country: autoCountry,
        customAttrs: Map<String, Object?>.of(customAttrs),
      );
    } catch (_) {
      // Last resort: never throw. Keep the caller-supplied identity even
      // when device collection itself somehow failed.
      try {
        return Targeting(
          userId: userId,
          customAttrs: Map<String, Object?>.of(customAttrs),
        );
      } catch (_) {
        return const Targeting();
      }
    }
  }
}
