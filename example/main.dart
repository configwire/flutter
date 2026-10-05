import 'package:configwire_flutter/configwire_flutter.dart';

/// Offline-first demo: `ensureInitialized: false` means no network, so this
/// runs in CI with no server. On a real device drop that line (default true)
/// to load the cache plus force-fetch on startup.
Future<void> main() async {
  final cw = await ConfigWireFlutter.createConfigWire(
    apiKey: 'YOUR_SDK_KEY', // sent as X-ConfigWire-Key, never printed
    env: 'dev',
    baseUrl: 'http://127.0.0.1:8090',
    defaults: {'launch_flag': false},
    customAttrs: {'plan': 'pro'},
    ensureInitialized: false,
  );

  assert(cw.getBool('launch_flag') == false);
  // NOTE: values printed, apiKey never printed.
  // ignore: avoid_print
  print(
    'launch_flag=${cw.getBool('launch_flag')} targeting=${cw.targeting}',
  );
  await cw.dispose();
}
