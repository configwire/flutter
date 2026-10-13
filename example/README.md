# ConfigWire Flutter example

Demo app for `configwire_flutter`: flag-gated UI over the pure-Dart `configwire` client.

Start at `lib/main.dart` (`ConfigWireExampleApp`) with defaults in
`lib/app_config.dart`. `lib/init_gate.dart` (`ConfigWireInitGate`) loads the
cache plus force-fetch on startup; `lib/config_wire_screen.dart` renders
`welcome_message` / `new_checkout` with `connectRealtime` + `onUpdate`;
`lib/widgets.dart` holds `SectionCard` / `DebugPanel` / `AllValuesView` /
`TargetingView`. `trackExposure` fires on flag views.

```bash
flutter run
```
