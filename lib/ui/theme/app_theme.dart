import 'package:material_ui/material_ui.dart';

class AppTheme {
  AppTheme._();

  /// Global runtime toggle updated when `SharedDeviceDatabase` changes.
  static bool isDark = true;

  // --- Surface & Structural Tokens ---
  static Color get scaffoldBg =>
      isDark ? const Color(0xFF141414) : const Color(0xFFF3F4F6);

  static Color get surface =>
      isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

  static Color get surfaceHigh =>
      isDark ? const Color(0xFF252526) : const Color(0xFFF9FAFB);

  static Color get surfaceElevated =>
      isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFFFFFF);

  static Color get border =>
      isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB);

  static Color get borderStrong =>
      isDark ? const Color(0xFF3E3E42) : const Color(0xFFD1D5DB);

  // --- Typography Tokens ---
  static Color get textPrimary =>
      isDark ? const Color(0xFFE0E0E0) : const Color(0xFF111827);

  static Color get textSecondary =>
      isDark ? const Color(0xFF9E9E9E) : const Color(0xFF4B5563);

  static Color get textMuted =>
      isDark ? const Color(0xFF6E6E6E) : const Color(0xFF6B7280);

  // --- Semantic & Action Tokens ---
  static Color get accent =>
      isDark ? const Color(0xFF007ACC) : const Color(0xFF0284C7);

  static Color get success =>
      isDark ? const Color(0xFF10B981) : const Color(0xFF059669);

  static Color get error =>
      isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);

  static Color get warning =>
      isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);

  static Color get info =>
      isDark ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);

  // --- ThemeData Builders ---
  static ThemeData get currentTheme => isDark ? darkTheme() : lightTheme();

  static ThemeData darkTheme() {
    final prev = isDark;
    isDark = true;
    final theme = _buildTheme(Brightness.dark);
    isDark = prev;
    return theme;
  }

  static ThemeData lightTheme() {
    final prev = isDark;
    isDark = false;
    final theme = _buildTheme(Brightness.light);
    isDark = prev;
    return theme;
  }

  static ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: Colors.white,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      surfaceContainerLowest: scaffoldBg,
      surfaceContainerLow: surface,
      surfaceContainer: surfaceHigh,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: isDark
          ? const Color(0xFF323232)
          : const Color(0xFFE5E7EB),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: colorScheme,
      dividerColor: border,
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: borderStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: borderStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
