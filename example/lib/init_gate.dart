import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter/material.dart';

import 'app_config.dart';
import 'config_wire_screen.dart';
import 'cw_theme.dart';

/// Init gate — async bootstrap before the main screen is shown.
class ConfigWireInitGate extends StatefulWidget {
  const ConfigWireInitGate({super.key});

  @override
  State<ConfigWireInitGate> createState() => _ConfigWireInitGateState();
}

class _ConfigWireInitGateState extends State<ConfigWireInitGate> {
  // Runtime-editable server config. Prefilled from [AppConfig] defaults so
  // the hardcoded constants remain as fallbacks; in-memory only, never
  // persisted (apiKey is never printed/logged).
  late final _baseUrlController = TextEditingController(
    text: AppConfig.baseUrl,
  );
  late final _apiKeyController = TextEditingController(text: AppConfig.apiKey);
  late final _envController = TextEditingController(text: AppConfig.env);

  ConfigWire? _cw;
  String? _error;
  bool _connecting = false;

  Future<void> _connect() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final env = _envController.text.trim();
    if (baseUrl.isEmpty || apiKey.isEmpty || env.isEmpty) {
      setState(() => _error = 'baseUrl, apiKey, and env must not be empty.');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    // Dispose any previous instance before re-init so reconnects are clean.
    final old = _cw;
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {
        // Best-effort: a failed dispose must not block reconnecting.
      }
      if (mounted) setState(() => _cw = null);
    }
    try {
      final cw = ConfigWire(
        apiKey: apiKey,
        // env written once here; configureFlutter attaches the default
        // prefs store namespaced by this env.
        env: env,
        baseUrl: baseUrl,
        defaults: AppConfig.defaults,
        verbose: true, // prints debug lines to the console
      );
      await cw.configureFlutter(
        // collectDevice: true — auto-fills platform, appVersion, locale,
        // country. Targeting stays anonymous; bucketing rides the
        // stable `?b=` slot.
      );
      // Cache load + force-fetch; never throws (falls back to cache/defaults).
      await cw.ensureInitialized();
      if (mounted) {
        setState(() {
          _cw = cw;
          _connecting = false;
        });
      } else {
        await cw.dispose();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _connecting = false;
        });
      }
    }
  }

  Future<void> _editConfig() async {
    final old = _cw;
    if (mounted) setState(() => _cw = null);
    if (old != null) {
      try {
        await old.dispose();
      } catch (_) {
        // Best-effort disconnect.
      }
    }
    if (mounted) setState(() => _error = null);
  }

  @override
  void dispose() {
    // Owns the ConfigWire lifetime: dispose it when the gate leaves the tree.
    // Controllers are in-memory only (never persisted).
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _envController.dispose();
    _cw?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cw = _cw;
    if (cw != null) {
      return ConfigWireScreen(cw: cw, onEditConfig: _editConfig);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text.rich(
          TextSpan(
            children: <TextSpan>[
              TextSpan(
                text: 'Config',
                style: TextStyle(
                  color: CwTheme.brandConfig,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: 'Wire',
                style: TextStyle(
                  color: CwTheme.brandWire,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: CwTheme.pageWash),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                decoration: CwTheme.card,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Server config',
                      style: TextStyle(
                        color: CwTheme.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Defaults come from AppConfig — edit to point at a real server without rebuilding.',
                      style: TextStyle(color: CwTheme.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _baseUrlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Base URL',
                        hintText: 'http://localhost:8090',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiKeyController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'API key',
                        hintText: 'SDK key (sent as X-ConfigWire-Key)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _envController,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Environment',
                        hintText: 'dev',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: CwTheme.danger),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: _connecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link),
                      label: Text(_connecting ? 'Connecting…' : 'Connect'),
                      onPressed: _connecting ? null : _connect,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
