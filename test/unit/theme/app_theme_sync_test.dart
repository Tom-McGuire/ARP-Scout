import 'dart:io';

import 'package:arp_scout/data/services/storage/suite_theme_sync_service.dart';
import 'package:arp_scout/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  tearDown(() {
    AppTheme.isDark = true;
  });

  group('AppTheme dynamic tokens', () {
    test('returns dark palette when isDark is true', () {
      AppTheme.isDark = true;
      expect(AppTheme.scaffoldBg, const Color(0xFF141414));
      expect(AppTheme.surface, const Color(0xFF1E1E1E));
      expect(AppTheme.surfaceHigh, const Color(0xFF252526));
      expect(AppTheme.border, const Color(0xFF2C2C2C));
      expect(AppTheme.textPrimary, const Color(0xFFE0E0E0));
      expect(AppTheme.textSecondary, const Color(0xFF9E9E9E));
      expect(AppTheme.textMuted, const Color(0xFF6E6E6E));
    });

    test('returns light palette when isDark is false', () {
      AppTheme.isDark = false;
      expect(AppTheme.scaffoldBg, const Color(0xFFF3F4F6));
      expect(AppTheme.surface, const Color(0xFFFFFFFF));
      expect(AppTheme.surfaceHigh, const Color(0xFFF9FAFB));
      expect(AppTheme.border, const Color(0xFFE5E7EB));
      expect(AppTheme.textPrimary, const Color(0xFF111827));
      expect(AppTheme.textSecondary, const Color(0xFF4B5563));
      expect(AppTheme.textMuted, const Color(0xFF6B7280));
    });

    test('lightTheme and darkTheme preserve AppTheme.isDark', () {
      AppTheme.isDark = false;
      final dark = AppTheme.darkTheme();
      expect(dark.brightness, Brightness.dark);
      expect(AppTheme.isDark, isFalse);

      AppTheme.isDark = true;
      final light = AppTheme.lightTheme();
      expect(light.brightness, Brightness.light);
      expect(AppTheme.isDark, isTrue);
    });
  });

  group('SuiteThemeSyncService', () {
    test('reads theme_mode from suite_settings and defaults to dark', () async {
      final dir = Directory.systemTemp.createTempSync('arp_scout_theme_test_');
      try {
        final dbPath = p.join(dir.path, 'shared_devices.db');

        // Missing file -> 'dark'
        expect(await SuiteThemeSyncService.getThemeMode(dbPath: dbPath), 'dark');

        // File without suite_settings -> 'dark'
        final db = sqlite3.open(dbPath);
        db.execute(
          'CREATE TABLE suite_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL);',
        );
        expect(await SuiteThemeSyncService.getThemeMode(dbPath: dbPath), 'dark');

        // Set to 'light'
        db.execute(
          "INSERT INTO suite_settings (key, value, updated_at) VALUES ('theme_mode', 'light', '2026-11-16T00:00:00Z');",
        );
        db.close();
        expect(
          await SuiteThemeSyncService.getThemeMode(dbPath: dbPath),
          'light',
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });
}
