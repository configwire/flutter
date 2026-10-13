/// ConfigWire Flutter Example
///
/// Demonstrates:
///   • ConfigWireFlutter.createConfigWire — one-call setup with
///     SharedPreferences cache and automatic device targeting.
///   • Feature flags gating real UI: [AppConfig.welcomeFlag] and
///     [AppConfig.newCheckoutFlag].
///   • connectRealtime / disconnectRealtime for live config pushes.
///   • onUpdate stream rebuilding the UI without a manual fetch.
///   • trackExposure called exactly where the flag value drives behavior.
///   • A debug panel showing fetch status, version, etag, and targeting.
///
/// Quick-start (replace the placeholder values):
///   flutter run
///
/// To point at a real ConfigWire server, edit [AppConfig].
library;

import 'package:flutter/material.dart';

import 'cw_theme.dart';
import 'init_gate.dart';

void main() {
  runApp(const ConfigWireExampleApp());
}

/// App root: admin-themed shell around the [ConfigWireInitGate].
class ConfigWireExampleApp extends StatelessWidget {
  const ConfigWireExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConfigWire Flutter Example',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: cwTheme(),
      home: const ConfigWireInitGate(),
    );
  }
}
