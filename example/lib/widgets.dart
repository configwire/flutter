// ignore_for_file: deprecated_member_use
// Displays the deprecated compat Targeting.country field for debugging.
import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:flutter/material.dart';

import 'cw_theme.dart';

/// Card with an admin-style head row (title over a `border-soft` divider).
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: CwTheme.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: CwTheme.borderSoft)),
            ),
            child: Text(
              title,
              style: const TextStyle(
                color: CwTheme.text,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

/// Monospace fetch/realtime status readout for the debug panel.
/// All rows read live client state ([ConfigWire.lastFetchStatus] and
/// [ConfigWire.realtime]'s `status`/`lastError`/`isConnected`) so the
/// panel always matches the server connection truth.
class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key, required this.cw});

  final ConfigWire cw;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (cw.lastFetchStatus) {
      FetchStatus.success => CwTheme.mint,
      FetchStatus.cached => CwTheme.accent,
      FetchStatus.throttled => CwTheme.warn,
      FetchStatus.error => CwTheme.danger,
      FetchStatus.none => CwTheme.mutedDim,
    };
    final rt = cw.realtime;
    final rtStatus = rt?.status;
    final rtColor = switch (rtStatus) {
      RealtimeStatus.connected => CwTheme.mint,
      RealtimeStatus.connecting => CwTheme.accent,
      RealtimeStatus.error => CwTheme.danger,
      RealtimeStatus.disconnected || null => CwTheme.mutedDim,
    };

    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall!
          .copyWith(fontFamily: 'monospace'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('lastFetchStatus', cw.lastFetchStatus.name, color: statusColor),
          _row('version', '${cw.version}'),
          _row('etag', cw.etag ?? '—'),
          _row('fetchTime', cw.fetchTime?.toLocal().toString() ?? '—'),
          _row(
            'realtime',
            rt == null ? 'disconnected' : rt.status.name,
            color: rtColor,
          ),
          if (rt != null) _row('realtime.isConnected', '${rt.isConnected}'),
          if (rt?.lastError != null)
            _row(
              'realtime.lastError',
              '${rt!.lastError}',
              color: CwTheme.danger,
            ),
          if (cw.getVariants().isNotEmpty)
            _row('variants', cw.getVariants().toString()),
        ],
      ),
    );
  }

  Widget _row(String key, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text('$key:', style: const TextStyle(color: CwTheme.muted)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}

/// Monospace dump of the live config view (`key: value` per row).
class AllValuesView extends StatelessWidget {
  const AllValuesView({super.key, required this.cw});

  final ConfigWire cw;

  @override
  Widget build(BuildContext context) {
    final all = cw.getAll();
    if (all.isEmpty) {
      return const Text('(no values yet)');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: all.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontFamily: 'monospace'),
              children: [
                TextSpan(
                  text: '${e.key}: ',
                  style: const TextStyle(color: CwTheme.muted),
                ),
                TextSpan(text: '${e.value}'),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Monospace dump of the sticky targeting attributes.
class TargetingView extends StatelessWidget {
  const TargetingView({super.key, required this.targeting});

  final Targeting targeting;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontFamily: 'monospace');
    final fields = <String, String>{
      'userId': targeting.userId.isEmpty ? '(anonymous)' : targeting.userId,
      'platform': targeting.platform.isEmpty ? '—' : targeting.platform,
      'appVersion': targeting.appVersion.isEmpty ? '—' : targeting.appVersion,
      'locale': targeting.locale.isEmpty ? '—' : targeting.locale,
      'country': targeting.country.isEmpty ? '—' : targeting.country,
      if (targeting.customAttrs.isNotEmpty)
        'customAttrs': targeting.customAttrs.toString(),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: fields.entries.map((e) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: RichText(
            text: TextSpan(
              style: style,
              children: [
                TextSpan(
                  text: '${e.key}: ',
                  style: const TextStyle(color: CwTheme.muted),
                ),
                TextSpan(text: e.value),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
