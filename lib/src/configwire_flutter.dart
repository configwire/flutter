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
/// Two shapes are supported:
///
/// * Bring-your-own [ConfigWire] (preferred): construct it in caller code,
///   then `await cw.configureFlutter(...)` resolves the install ID +
///   device targeting, calls `cw.setTargeting`, and optionally runs
///   `cw.ensureInitialized()`.
/// * One-shot: `await ConfigWireFlutter.createConfigWire(...)`
///   (deprecated, use `cw.configureFlutter` instead) builds a prefs-backed
///   [ConfigWire] and runs the same init.
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
/// Like the core `ConfigWire` constructor, configuring never fetches:
/// `ensureInitialized` defaults to `false` (targeting only — hermetic, no
/// network). Pass `true`, or call [ConfigWire.ensureInitialized]
/// afterwards, to load the cache plus force-fetch against [baseUrl].
///
/// `userId` persistence: only the install ID is saved to
/// `SharedPreferencesAsync` under
/// `'<prefixCache>.<Uri.encodeComponent(env)>.userId'` and restored on
/// later launches. Nothing else is persisted — never device fields.
///
/// Prefs keys share the `<prefixCache>.<env>.<suffix>` scheme (`suffix` is
/// `cache` for values, `userId` for the install ID); pass a custom
/// [prefixCache] to isolate multiple SDK instances in one app. When callers
/// supply their own [ConfigWire] with a [SharedPreferencesCacheStore], the
/// [prefixCache] passed to `cw.configureFlutter` must match the one
/// used for that store so the userId key lines up with `cw.env`. Same for
/// [prefs]: a custom `prefs` passed to either side must be passed to both,
/// or cache and install-ID silently read/write different backends.
///
/// When nothing is persisted, [idGenerator] (default [defaultIdGenerator]:
/// a random 15-char lowercase `[a-z0-9]` ID) supplies the value so the
/// install stays stably bucketed.
abstract final class ConfigWireFlutter {
  /// Per-instance flutter-targeting state. [ConfigWire] lives in the
  /// pure-Dart package and cannot carry Flutter init flags, so the guard
  /// lives here. Targeting resolves once per [ConfigWire] instance
  /// (first-call-wins; later calls join the in-flight future or no-op).
  /// The final fetch step is NOT guarded here — it delegates to
  /// [ConfigWire.ensureInitialized], which is itself idempotent.
  static final Expando<Future<void>> _flutterTargetingInFlight =
      Expando<Future<void>>('configwire_flutter_targeting_in_flight');
  static final Expando<bool> _flutterTargetingDone = Expando<bool>(
    'configwire_flutter_targeting_done',
  );

  /// Resolves Flutter-side targeting for [cw], then optionally runs
  /// [ConfigWire.ensureInitialized].
  ///
  /// Safe to call multiple times per [cw]: targeting resolves once
  /// (first-call-wins; concurrent callers join the same in-flight future
  /// and later callers no-op with their params ignored). The fetch step
  /// delegates to [ConfigWire.ensureInitialized] every time, which
  /// dedupes itself — so a first call with `ensureInitialized: false`
  /// (targeting only) followed by a call with `true` still fetches.
  ///
  /// Never throws: persisted-ID I/O swallows errors, [idGenerator]
  /// failures degrade to anonymous, device collection degrades
  /// (per-field for the default collector, identity-only for a throwing
  /// custom collector), and [ConfigWire.ensureInitialized] never throws.
  static Future<void> _configureFlutter(
    ConfigWire cw, {
    String Function() idGenerator = defaultIdGenerator,
    Map<String, Object?>? customAttrs,
    bool collectDevice = true,
    String prefixCache = 'configwire',
    bool ensureInitialized = false,
    SharedPreferencesAsync? prefs,
    DeviceTargetingCollector? collector,
  }) async {
    if (_flutterTargetingDone[cw] == true) {
      if (ensureInitialized) await cw.ensureInitialized();
      return;
    }
    final inFlight = _flutterTargetingInFlight[cw];
    if (inFlight != null) {
      await inFlight;
      if (ensureInitialized) await cw.ensureInitialized();
      return;
    }
    final future = _resolveFlutterTargeting(
      cw,
      idGenerator: idGenerator,
      customAttrs: customAttrs,
      collectDevice: collectDevice,
      prefixCache: prefixCache,
      prefs: prefs,
      collector: collector,
    );
    _flutterTargetingInFlight[cw] = future;
    try {
      await future;
      _flutterTargetingDone[cw] = true;
    } finally {
      _flutterTargetingInFlight[cw] = null;
    }
    if (ensureInitialized) await cw.ensureInitialized();
  }

  static Future<void> _resolveFlutterTargeting(
    ConfigWire cw, {
    required String Function() idGenerator,
    required Map<String, Object?>? customAttrs,
    required bool collectDevice,
    required String prefixCache,
    required SharedPreferencesAsync? prefs,
    required DeviceTargetingCollector? collector,
  }) async {
    final resolvedPrefs = prefs ?? SharedPreferencesAsync();
    var userId = await loadPersistedUserId(
      prefs: resolvedPrefs,
      env: cw.env,
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
          prefs: resolvedPrefs,
          env: cw.env,
          userId: generated,
          prefixCache: prefixCache,
        );
      } else {
        userId = '';
      }
    }
    Targeting targeting;
    if (collectDevice) {
      // A custom collector may throw; degrade to identity-only rather than
      // breaking the never-throws contract (the default collector already
      // degrades per-field internally and never throws itself).
      try {
        targeting = await (collector ?? DeviceTargetingCollector())
            .resolveDeviceTargeting(userId, customAttrs ?? {});
      } catch (_) {
        targeting = Targeting(
          userId: userId,
          customAttrs: Map<String, Object?>.of(customAttrs ?? {}),
        );
      }
    } else {
      targeting = Targeting(
        userId: userId,
        customAttrs: Map<String, Object?>.of(customAttrs ?? {}),
      );
    }
    cw.setTargeting(targeting);
  }

  /// Deprecated: construct your own [ConfigWire] and call
  /// `await cw.configureFlutter(...)` instead.
  ///
  /// Note the default flip: `createConfigWire` fetches unless
  /// `ensureInitialized: false`, while `configureFlutter` only targets
  /// unless `ensureInitialized: true` — to preserve this method's
  /// behavior, fetch explicitly:
  /// ```dart
  /// final cw = ConfigWire(
  ///   apiKey: apiKey, env: env, baseUrl: baseUrl, defaults: defaults,
  ///   store: SharedPreferencesCacheStore(
  ///     env: env, prefixCache: prefixCache,
  ///   ),
  /// );
  /// await cw.configureFlutter(customAttrs: customAttrs);
  /// await cw.ensureInitialized();
  /// ```
  @Deprecated('Use your own ConfigWire + cw.configureFlutter() instead')
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
    final cw = ConfigWire(
      apiKey: apiKey,
      env: env,
      baseUrl: baseUrl,
      defaults: defaults,
      store: SharedPreferencesCacheStore(
        prefs: prefs,
        env: env,
        prefixCache: prefixCache,
      ),
      minimumFetchInterval: minimumFetchInterval ?? const Duration(hours: 12),
      fetchTimeout: fetchTimeout ?? const Duration(seconds: 60),
      verbose: verbose,
    );
    await _configureFlutter(
      cw,
      idGenerator: idGenerator,
      customAttrs: customAttrs,
      collectDevice: collectDevice,
      prefixCache: prefixCache,
      ensureInitialized: ensureInitialized,
      prefs: prefs,
    );
    return cw;
  }
}

/// Flutter entry point on your own [ConfigWire]:
/// `await cw.configureFlutter(...)` resolves the install ID + device
/// targeting, calls `cw.setTargeting`, and optionally runs
/// [ConfigWire.ensureInitialized].
extension ConfigWireFlutterExtension on ConfigWire {
  /// One-shot Flutter init for this [ConfigWire].
  ///
  /// Safe to call multiple times: targeting resolves once (first-call-wins;
  /// concurrent callers join the same in-flight future and later callers
  /// no-op with their params ignored). Like the core constructor,
  /// configuring never fetches by default (`ensureInitialized: false`);
  /// pass `true` or call [ConfigWire.ensureInitialized] afterwards for
  /// the cache load plus forced fetch.
  ///
  /// Never throws (see [ConfigWireFlutter]).
  Future<void> configureFlutter({
    String Function() idGenerator = defaultIdGenerator,
    Map<String, Object?>? customAttrs,
    bool collectDevice = true,
    String prefixCache = 'configwire',
    bool ensureInitialized = false,
    SharedPreferencesAsync? prefs,
    DeviceTargetingCollector? collector,
  }) => ConfigWireFlutter._configureFlutter(
    this,
    idGenerator: idGenerator,
    customAttrs: customAttrs,
    collectDevice: collectDevice,
    prefixCache: prefixCache,
    ensureInitialized: ensureInitialized,
    prefs: prefs,
    collector: collector,
  );
}
