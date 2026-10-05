import 'package:configwire/configwire.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_targeting.dart';
import 'prefs_store.dart';

/// Factory namespace for building a fully-wired [ConfigWire] on Flutter.
///
/// One call supplies the two Flutter-specific pieces the pure-Dart client
/// cannot provide on its own: a [SharedPreferencesAsync]-backed [CacheStore]
/// and device-derived [Targeting]. The returned [ConfigWire] is a plain
/// instance — construct-then-[ConfigWire.setTargeting], never a subclass —
/// so every `client/dart` API behaves exactly as documented there.
///
/// Targeting precedence:
/// * [explicitTargeting] given: used as-is; device collection is skipped.
/// * [collectDevice] true (default), no explicit targeting: explicit
///   non-empty scalars win per-field over auto-collected values;
///   customAttrs comes from the explicit input.
/// * [collectDevice] false, no explicit targeting: anonymous except for
///   `userId`/`customAttrs`.
///
/// Pass `ensureInitialized: false` in tests to stay hermetic: `true` (the
/// default) performs a real forced fetch against [baseUrl].
abstract final class ConfigWireFlutter {
  static Future<ConfigWire> createConfigWire({
    required String apiKey,
    required String env,
    required String baseUrl,
    Map<String, Object?> defaults = const {},
    String? userId,
    Targeting? explicitTargeting,
    Map<String, Object?>? customAttrs,
    bool collectDevice = true,
    String? cacheKey,
    Duration? minimumFetchInterval,
    Duration? fetchTimeout,
    bool verbose = false,
    bool ensureInitialized = true,
  }) async {
    final prefs = SharedPreferencesAsync();
    final store = SharedPreferencesCacheStore(
      prefs: prefs,
      env: env,
      cacheKey: cacheKey,
    );

    final Targeting targeting;
    final explicit = explicitTargeting;
    if (explicit != null) {
      targeting = explicit;
    } else if (collectDevice) {
      final collector = DeviceTargetingCollector();
      targeting = await collector.resolveDeviceTargeting(
        explicit: Targeting(
          userId: userId ?? '',
          customAttrs: customAttrs ?? {},
        ),
      );
    } else {
      targeting = Targeting(
        userId: userId ?? '',
        customAttrs: customAttrs ?? {},
      );
    }

    final cw = ConfigWire(
      apiKey: apiKey,
      env: env,
      baseUrl: baseUrl,
      defaults: defaults,
      store: store,
      minimumFetchInterval:
          minimumFetchInterval ?? const Duration(hours: 12),
      fetchTimeout: fetchTimeout ?? const Duration(seconds: 60),
      verbose: verbose,
    );
    cw.setTargeting(targeting);
    if (ensureInitialized) {
      await cw.ensureInitialized();
    }
    return cw;
  }
}
