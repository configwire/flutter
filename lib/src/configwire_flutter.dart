import 'package:configwire/configwire.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_targeting.dart';
import 'prefs_store.dart';
import 'user_store.dart';

/// Factory namespace for building a fully-wired [ConfigWire] on Flutter.
///
/// One call supplies the two Flutter-specific pieces the pure-Dart client
/// cannot provide on its own: a [SharedPreferencesAsync]-backed [CacheStore]
/// and device-derived [Targeting]. The returned [ConfigWire] is a plain
/// instance — construct-then-[ConfigWire.setTargeting], never a subclass —
/// so every `client/dart` API behaves exactly as documented there.
///
/// Identity: a stable install ID, customizable only via [idGenerator].
/// * First launch with nothing persisted: [idGenerator] supplies the ID,
///   which is then persisted. Later launches reuse the persisted value
///   and never call the generator again.
/// * [idGenerator] returning `''` stays anonymous for that launch and
///   pins nothing, so the next launch tries again.
/// * [collectDevice] (default true) fills platform/appVersion/locale/country
///   around the ID; false skips device collection entirely.
/// * Only the install ID is ever persisted — never device fields.
///
/// Pass `ensureInitialized: false` in tests to stay hermetic: `true` (the
/// default) performs a real forced fetch against [baseUrl].
///
/// `userId` persistence: only the install ID is saved to
/// `SharedPreferencesAsync` under
/// `'<prefixCache>.<Uri.encodeComponent(env)>.userId'` and restored on
/// later launches. Nothing else is persisted — never device fields.
///
/// Prefs keys share the `<prefixCache>.<env>.<suffix>` scheme (`suffix` is
/// `cache` for values, `userId` for the install ID); pass a custom
/// [prefixCache] to isolate multiple SDK instances in one app.
///
/// When nothing is persisted, [idGenerator] (default [defaultIdGenerator]:
/// a random 15-char lowercase `[a-z0-9]` ID) supplies the value so the
/// install stays stably bucketed.
abstract final class ConfigWireFlutter {
  static Future<ConfigWire> createConfigWire({
    required String apiKey,
    required String env,
    required String baseUrl,
    Map<String, Object?> defaults = const {},
    String Function() idGenerator = defaultIdGenerator,
    Map<String, Object?>? customAttrs,
    bool collectDevice = true,
    String prefixCache = 'configwire',
    Duration? minimumFetchInterval,
    Duration? fetchTimeout,
    bool verbose = false,
    bool ensureInitialized = true,
  }) async {
    final prefs = SharedPreferencesAsync();
    final store = SharedPreferencesCacheStore(
      prefs: prefs,
      env: env,
      prefixCache: prefixCache,
    );

    final Targeting targeting;
    // The install ID is the only `userId` ever persisted. A custom
    // idGenerator supplies the first-run value; later launches reuse the
    // persisted value without calling it again.
    var userId = await loadPersistedUserId(
      prefs: prefs,
      env: env,
      prefixCache: prefixCache,
    );
    if (userId == null) {
      String generated = '';
      try {
        generated = idGenerator().trim();
      } catch (_) {
        generated = '';
      }
      if (generated.isNotEmpty) {
        userId = generated;
        await savePersistedUserId(
          prefs: prefs,
          env: env,
          userId: generated,
          prefixCache: prefixCache,
        );
      } else {
        // The generator declined: anonymous this launch, nothing pinned,
        // so the next launch tries again.
        userId = '';
      }
    }
    // collectDevice:false skips device collection entirely. customAttrs
    // comes from the caller's explicit input (never persisted).
    if (collectDevice) {
      targeting = await DeviceTargetingCollector().resolveDeviceTargeting(
        userId,
        customAttrs ?? {},
      );
    } else {
      targeting = Targeting(
        userId: userId,
        customAttrs: Map<String, Object?>.of(customAttrs ?? {}),
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
