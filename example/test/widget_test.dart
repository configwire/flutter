import 'package:configwire_flutter/configwire_flutter.dart';
import 'package:example/config_wire_screen.dart';
import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // SharedPreferences needs a mock backing store in tests.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ConfigWireExampleApp', () {
    testWidgets('shows server config form on boot', (tester) async {
      // The init gate boots to an editable server-config form prefilled
      // from AppConfig defaults — no rebuild needed to point at a server.
      await tester.pumpWidget(const ConfigWireExampleApp());
      expect(find.text('Server config'), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Base URL'), findsOneWidget);
      expect(find.text('API key'), findsOneWidget);
      expect(find.text('Environment'), findsOneWidget);
    });
  });

  group('ConfigWireScreen', () {
    late ConfigWire cw;

    setUp(() async {
      // Build a hermetic ConfigWire instance: no real fetch (ensureInitialized
      // is skipped), in-memory store only.
      cw = ConfigWire(
        apiKey: 'test-key',
        env: 'test',
        baseUrl: 'http://localhost:9999',
        defaults: const {
          'welcome_message': 'Hello from defaults!',
          'new_checkout': false,
        },
        minimumFetchInterval: Duration.zero,
      );
    });

    tearDown(() async {
      await cw.dispose();
    });

    testWidgets('renders welcome message from defaults', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ConfigWireScreen(cw: cw)));
      await tester.pump();

      expect(find.text('Hello from defaults!'), findsOneWidget);
    });

    testWidgets('shows "Disabled" when new_checkout is false', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ConfigWireScreen(cw: cw)));
      await tester.pump();

      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('shows debug info panel', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ConfigWireScreen(cw: cw)));
      await tester.pump();

      // The debug panel header is always visible.
      expect(find.text('Debug info'), findsOneWidget);
    });

    testWidgets('shows fetchAndActivate button', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ConfigWireScreen(cw: cw)));
      await tester.pump();

      // Button is at the bottom of the ListView — scroll to reveal it.
      await tester.scrollUntilVisible(
        find.text('fetchAndActivate'),
        500,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('fetchAndActivate'), findsOneWidget);
    });

    testWidgets('checkout button tap increments tap count', (tester) async {
      await tester.pumpWidget(MaterialApp(home: ConfigWireScreen(cw: cw)));
      await tester.pump();

      // Initial state — taps: 0
      expect(find.textContaining('taps: 0'), findsOneWidget);

      // Tap the checkout button.
      await tester.tap(find.byIcon(Icons.shopping_cart));
      await tester.pumpAndSettle();

      // After one tap — taps: 1
      expect(find.textContaining('taps: 1'), findsOneWidget);
    });

    testWidgets('shows wifi_off icon when realtime is disconnected', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: ConfigWireScreen(cw: cw)));
      await tester.pump();

      // Initially disconnected — the AppBar shows a wifi_off icon.
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('shows all config values section with flag keys', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: ConfigWireScreen(cw: cw)));
      await tester.pump();

      expect(find.text('All config values'), findsOneWidget);
      // welcome_message should appear in the values list (rendered once there).
      expect(find.textContaining('welcome_message'), findsWidgets);
      // new_checkout appears in multiple places (section header, hint text,
      // and the values list) — just assert it exists somewhere.
      expect(find.textContaining('new_checkout'), findsWidgets);
    });

    testWidgets('shows active targeting section after scrolling', (
      tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: ConfigWireScreen(cw: cw)));
      await tester.pump();

      // The section may be off-screen in the ListView — scroll to find it.
      await tester.scrollUntilVisible(
        find.text('Active targeting'),
        500,
        scrollable: find.byType(Scrollable),
      );
      await tester.pump();

      expect(find.text('Active targeting'), findsOneWidget);
    });
  });
}
