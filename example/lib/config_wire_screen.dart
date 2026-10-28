import 'dart:async';

import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter/material.dart';

import 'app_config.dart';
import 'cw_theme.dart';
import 'widgets.dart';

/// Main screen: flag-gated UI, realtime toggle, fetch actions, and
/// debug/targeting readouts.
class ConfigWireScreen extends StatefulWidget {
  const ConfigWireScreen({super.key, required this.cw, this.onEditConfig});

  final ConfigWire cw;

  /// Optional entry point back to the runtime server-config form.
  /// The init gate supplies this to dispose [cw] and show the form again.
  final VoidCallback? onEditConfig;

  @override
  State<ConfigWireScreen> createState() => _ConfigWireScreenState();
}

class _ConfigWireScreenState extends State<ConfigWireScreen> {
  // Real connection truth lives on the client (`cw.realtime?.status` /
  // `isConnected`); no local bool — AppBar + DebugPanel re-read it on
  // every build so they can never drift from the SSE state.

  // A counter to show the "new checkout" feature-flag path being exercised.
  int _checkoutTaps = 0;

  // Holds the onUpdate subscription so we can cancel it on dispose.
  late final _updateSub = widget.cw.onUpdate.listen((_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    // Subscribe to config updates pushed by the realtime SSE/poll updater.
    // Each emission means a server 200 replaced values — setState rebuilds the
    // flag-gated UI without the user having to tap anything.
    _updateSub; // access the lazy field to start the subscription.
  }

  @override
  void dispose() {
    // Cancel the onUpdate subscription and stop the realtime poll/stream
    // timer. ConfigWire.dispose() stays the init gate's responsibility,
    // but disconnect here so removing this screen alone never leaks the
    // periodic timer when the shared instance outlives the widget.
    _updateSub.cancel();
    // Fire-and-forget: dispose() is sync, disconnect is best-effort.
    unawaited(widget.cw.disconnectRealtime());
    super.dispose();
  }

  Future<void> _fetchAndActivate() async {
    await widget.cw.fetchAndActivate();
    if (mounted) setState(() {});
  }

  Future<void> _toggleRealtime() async {
    if (widget.cw.realtime != null) {
      await widget.cw.disconnectRealtime();
      if (mounted) setState(() {});
    } else {
      // pollInterval: 30s for demo purposes; production default is 15 min.
      await widget.cw.connectRealtime(
        pollInterval: const Duration(seconds: 30),
      );
      if (mounted) setState(() {});
    }
  }

  // Simulate a "checkout" tap — tracks an exposure right where the flag value
  // drives behavior (the correct place per the SDK docs).
  Future<void> _onCheckoutTap() async {
    setState(() => _checkoutTaps++);
    // ✅ Track exposure *where* the flag value actually influences behavior.
    await widget.cw.trackExposure(AppConfig.newCheckoutFlag);
    if (!mounted) return;
    final newCheckout = widget.cw.getBool(AppConfig.newCheckoutFlag) ?? false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newCheckout
              ? '🛒 New checkout flow activated!'
              : '🛍️ Legacy checkout flow',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cw = widget.cw;
    final welcomeMsg =
        cw.getString(AppConfig.welcomeFlag) ??
        AppConfig.defaults[AppConfig.welcomeFlag] as String;
    final newCheckout = cw.getBool(AppConfig.newCheckoutFlag) ?? false;
    final targeting = cw.targeting;
    // Real server-connection state: fetch outcome + live SSE status.
    // Re-read on every build (setState fires after fetch, toggle, onUpdate).
    final rt = cw.realtime;
    final realtimeConnected = rt?.isConnected ?? false;
    final realtimeStatusName = rt?.status.name ?? 'disconnected';
    final realtimeError = rt?.lastError;
    final appBarTooltip = rt == null
        ? 'Realtime disconnected (fetch: ${cw.lastFetchStatus.name}) — tap to connect'
        : 'Realtime $realtimeStatusName (fetch: ${cw.lastFetchStatus.name})'
              '${realtimeError != null ? ' — $realtimeError' : ''} — tap to disconnect';

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
        actions: [
          if (widget.onEditConfig != null)
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Server config — tap to disconnect and edit',
              onPressed: widget.onEditConfig,
            ),
          IconButton(
            icon: Icon(realtimeConnected ? Icons.wifi : Icons.wifi_off),
            tooltip: appBarTooltip,
            onPressed: _toggleRealtime,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: CwTheme.pageWash),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Welcome banner (String flag) ──────────────────────────────────
            SectionCard(
              title: 'String flag: ${AppConfig.welcomeFlag}',
              child: Text(
                welcomeMsg,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),

            const SizedBox(height: 12),

            // ── Bool flag: new_checkout ───────────────────────────────────────
            SectionCard(
              title: 'Bool flag: ${AppConfig.newCheckoutFlag}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        newCheckout ? Icons.check_circle : Icons.cancel,
                        color: newCheckout ? CwTheme.mint : CwTheme.mutedDim,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        newCheckout ? 'Enabled' : 'Disabled',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.shopping_cart),
                    label: Text(
                      newCheckout
                          ? 'New Checkout (taps: $_checkoutTaps)'
                          : 'Legacy Checkout (taps: $_checkoutTaps)',
                    ),
                    onPressed: _onCheckoutTap,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Each tap calls trackExposure("${AppConfig.newCheckoutFlag}").',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Debug panel ───────────────────────────────────────────────────
            SectionCard(
              title: 'Debug info',
              child: DebugPanel(cw: cw),
            ),

            const SizedBox(height: 12),

            // ── All values ────────────────────────────────────────────────────
            SectionCard(
              title: 'All config values',
              child: AllValuesView(cw: cw),
            ),

            const SizedBox(height: 12),

            // ── Targeting info ────────────────────────────────────────────────
            SectionCard(
              title: 'Active targeting',
              child: TargetingView(targeting: targeting),
            ),

            const SizedBox(height: 24),

            // ── Actions ───────────────────────────────────────────────────────
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('fetchAndActivate'),
              onPressed: _fetchAndActivate,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: Icon(realtimeConnected ? Icons.wifi_off : Icons.wifi),
              label: Text(
                realtimeConnected ? 'Disconnect realtime' : 'Connect realtime',
              ),
              onPressed: _toggleRealtime,
            ),
          ],
        ),
      ),
    );
  }
}
