// T8 backward-compat regression guards (flutter wrapper): deprecated
// shim entry points keep working verbatim when a stable-bucket row is
// already persisted — no userId regen, no throw, bucket still reaches
// the T5 fetch wire. Additive only; pins in backward_compat_test.dart
// and bucket_persistence_test.dart are never rewritten.
//
// Already pinned elsewhere (referenced, not duplicated):
//   - (a)-(d) shim shapes + default/custom-key persistence:
//     backward_compat_test.dart
//   - bucket row round-trip / per-env isolation / reinstall-absent /
//     malformed-absent / fallback merge / userId->?userHash= send rule:
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
    test(
      'createConfigWire reuses the pinned userId beside a bucket row',
      () async {
        final prefs = SharedPreferencesAsync();
        await prefs.setString('configwire.dev.userId', 'abc123def456ghi');
        await prefs.setString('configwire.dev.bucket', '42');
        var calls = 0;
        String generator() {
          calls++;
          return 'regenerated-id-000';
        }

        final cw = await ConfigWireFlutter.createConfigWire(
          apiKey: 'sk-test',
          env: 'dev',
          baseUrl: 'http://127.0.0.1:8090',
          collectDevice: false,
          ensureInitialized: false,
          idGenerator: generator,
        );
        expect(cw.targeting.userId, equals('abc123def456ghi'));
        expect(calls, equals(0), reason: 'persisted ID must win, no regen');
        await cw.dispose();
      },
    );

    test(
      'configureFlutter(prefs:, prefixCache:) keeps ID + bucket fallback',
      () async {
        final prefs = SharedPreferencesAsync();
        await prefs.setString('custom.dev.userId', 'abc123def456ghi');
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
          idGenerator: () => throw StateError('must reuse persisted ID'),
        );
        expect(cw.targeting.userId, equals('abc123def456ghi'));
        expect(cw.bucket, equals(77));
        await cw.dispose();
      },
    );
  });
}
