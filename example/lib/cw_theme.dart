import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Admin theme — design tokens mirrored from
// `configwire/pb_public/styles.css` (`:root`). The Admin UI is dark-only
// (`color-scheme: dark`), so this example forces the dark theme too.
// ---------------------------------------------------------------------------

/// Admin design tokens (`:root` in `pb_public/styles.css`).
abstract final class CwTheme {
  static const bg = Color(0xFF141922);
  static const panel = Color(0xFF1A1F2A);
  static const panel2 = Color(0xFF222834);
  static const panel3 = Color(0xFF2A3345);
  static const border = Color(0xFF2E3850);
  static const borderSoft = Color(0xFF263049);
  static const text = Color(0xFFEEF2FA);
  static const muted = Color(0xFF9AA6C0);
  static const mutedDim = Color(0xFF6F7B96);
  static const accent = Color(0xFF3B82F6);
  static const mint = Color(0xFF5EEAD4);
  static const danger = Color(0xFFF87171);
  static const warn = Color(0xFFFBBF24);
  static const brandConfig = Color(0xFF9DA4AD);
  static const brandWire = Color(0xFF3A9AEE);

  /// Soft page wash behind the list (the `body` radial gradients).
  static const pageWash = RadialGradient(
    center: Alignment(0.9, -1.2),
    radius: 1.1,
    colors: <Color>[Color(0x1F3B82F6), Color(0x0F5EEAD4), bg],
    stops: <double>[0.0, 0.35, 0.7],
  );

  /// Card surface (`.card`): panel fill + border + small shadow.
  static BoxDecoration get card => BoxDecoration(
    color: panel,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: border),
    boxShadow: const <BoxShadow>[
      BoxShadow(
        color: Color(0x59000000),
        blurRadius: 12,
        offset: Offset(0, 2),
      ),
    ],
  );
}

/// Dark Material theme from the admin tokens (`.btn.primary` → accent,
/// `.btn.secondary` → panel-2, focus ring → mint).
ThemeData cwTheme() {
  const scheme = ColorScheme.dark(
    primary: CwTheme.accent,
    onPrimary: Colors.white,
    secondary: CwTheme.mint,
    onSecondary: Color(0xFF08111F),
    surface: CwTheme.panel,
    onSurface: CwTheme.text,
    error: CwTheme.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: CwTheme.bg,
    cardColor: CwTheme.panel,
    dividerColor: CwTheme.borderSoft,
    appBarTheme: const AppBarTheme(
      backgroundColor: CwTheme.panel,
      foregroundColor: CwTheme.text,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CwTheme.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 36),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: CwTheme.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 36),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: CwTheme.panel2,
        foregroundColor: CwTheme.text,
        side: const BorderSide(color: CwTheme.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 36),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: CwTheme.muted),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: CwTheme.panel3,
      contentTextStyle: TextStyle(color: CwTheme.text, fontSize: 13),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CwTheme.mint,
    ),
  );
}
