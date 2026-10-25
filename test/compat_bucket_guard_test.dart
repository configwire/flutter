// T8 backward-compat regression guards (flutter wrapper): deprecated
// shim entry points keep working verbatim when a stable-bucket row is
// already persisted — no throw, bucket still reaches the T5 fetch wire.
// Additive only; pins in backward_compat_test.dart and
// bucket_persistence_test.dart are never rewritten.
//
// Already pinned elsewhere (referenced, not duplicated):
//   - (a)-(d) shim shapes + default/custom-key persistence:
//     backward_compat_test.dart
//   - bucket row round-trip / per-env isolation / reinstall-absent /
//     malformed-absent / fallback merge / no-`userHash` emission rule:
//     bucket_persistence_test.dart
// ignore_for_file: deprecated_member_use
import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('compat: shims coexist with a persisted bucket', () {
    test('createConfigWire stays anonymous beside a bucket fallback', () async {
      final prefs = SharedPreferencesAsync();
      await prefs.setString('configwire.dev.bucket', '42');

      final cw = await ConfigWireFlutter.createConfigWire(
        apiKey: 'sk-test',
        env: 'dev',
        baseUrl: 'http://127.0.0.1:8090',
        collectDevice: false,
        ensureInitialized: false,
      );
      // Anonymous by construction: targeting carries no identity,
      // query carries no userHash.
      expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
      await cw.dispose();
    });

    test(
      'configureFlutter(prefs:, prefixCache:) keeps the bucket fallback',
      () async {
        final prefs = SharedPreferencesAsync();
        await prefs.setString('custom.dev.bucket', '77');
        final cw = ConfigWire(
          apiKey: 'sk-test',
          env: 'dev',
          baseUrl: 'http://127.0.0.1:8090',
          store: MemoryCacheStore(),
        );
        await cw.configureFlutter(
          prefs: prefs,
          prefixCache: 'custom',
          collectDevice: false,
          ensureInitialized: true,
        );
        expect(cw.targeting.toQueryParameters(), isNot(contains('userHash')));
        expect(cw.bucket, equals(77));
        await cw.dispose();
      },
    );
  });
}
