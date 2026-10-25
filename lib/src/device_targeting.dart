import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:configwire/configwire.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';

/// Injectable seam for the device locale source.
///
/// Defaults to [PlatformDispatcher.instance] ([_PlatformDispatcherLocale]).
/// Tests inject a fake; no device exists in CI.
abstract class DeviceLocaleDispatcher {
  Locale get locale;
}

/// Injectable seam for the app-version source.
///
/// Defaults to [PackageInfoPlatform.instance] ([_PackageInfoVersionReader]).
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

/// Real [AppVersionReader] over [PackageInfoPlatform.instance.getAll].
///
/// Failure degrades to `''` (omitted from the query) instead of throwing.
class _PackageInfoVersionReader implements AppVersionReader {
  @override
  Future<String> fetchVersion() async {
    try {
      return (await PackageInfoPlatform.instance.getAll()).version;
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
/// * Targeting is always anonymous: the former install-ID surface has been
///   removed, so nothing identity-like enters the URL — bucketing rides
///   the stable `?b=` slot.
/// * [customAttrs] pass through untouched (a defensive copy
///   for the map); no device keys are ever added to `customAttrs`.
/// * Never throws: each seam failure degrades its field; the outer
///   try/catch returns customAttrs-only targeting as a last resort.
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

  /// Resolves device-derived [Targeting] for fetch query params.
  ///
  /// Targeting is always anonymous: the former install-ID surface has been
  /// removed, so nothing passed here reaches the wire as identity —
  /// bucketing rides the stable `?b=` slot.
  Future<Targeting> resolveDeviceTargeting(
    Map<String, Object?> customAttrs,
  ) async {
    try {
      final autoPlatform = _normalizePlatform(_platform, _isWeb);

      // appVersion: strip +build metadata (server strict-semver-compares).
      var autoVersion = '';
      try {
        autoVersion = (await _packageInfo.fetchVersion())
            .trim()
            .split('+')
            .first
            .trim();
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
        platform: autoPlatform,
        appVersion: autoVersion,
        locale: autoLocale,
        country: autoCountry,
        customAttrs: Map<String, Object?>.of(customAttrs),
      );
    } catch (_) {
      // Last resort: never throw. Device collection itself somehow
      // failed, so return customAttrs-only targeting (anonymous — no
      // identity is fed toward the wire).
      try {
        return Targeting(customAttrs: Map<String, Object?>.of(customAttrs));
      } catch (_) {
        return const Targeting();
      }
    }
  }
}
