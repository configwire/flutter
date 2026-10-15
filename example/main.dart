import 'package:configwire_flutter/configwire_flutter.dart';

/// Offline-first demo: with no server running, the startup fetch fails
/// gracefully and the demo serves defaults. Point `baseUrl` at a real
/// server to load the cache plus force-fetch on startup.
Future<void> main() async {
  final cw = ConfigWire(
    apiKey: 'YOUR_SDK_KEY', // sent as X-ConfigWire-Key, never printed
    env: 'dev',
    baseUrl: 'http://127.0.0.1:8090',
    defaults: {'launch_flag': false},
    store: SharedPreferencesCacheStore(env: 'dev'),
  );
  await cw.configureFlutter(customAttrs: {'plan': 'pro'});
  await cw.ensureInitialized();

  assert(cw.getBool('launch_flag') == false);
  // NOTE: values printed, apiKey never printed.
  // ignore: avoid_print
  print('launch_flag=${cw.getBool('launch_flag')} targeting=${cw.targeting}');
  await cw.dispose();
}
