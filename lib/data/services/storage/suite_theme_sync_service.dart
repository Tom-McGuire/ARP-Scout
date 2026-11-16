import 'dart:io';

import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:sqlite3/sqlite3.dart';

/// Reads the synchronized Network Suite theme mode (`'dark'` or `'light'`)
/// from `suite_settings` inside the shared `shared_devices.db`.
class SuiteThemeSyncService {
  SuiteThemeSyncService._();

  /// Returns `'dark'` (default) or `'light'`.
  static Future<String> getThemeMode({String? dbPath}) async {
    final targetPath =
        dbPath ??
        SharedDeviceDatabase.instance.databasePath ??
        SharedDeviceDatabase.getDefaultDatabasePath();

    if (targetPath == ':memory:' || !File(targetPath).existsSync()) {
      return 'dark';
    }

    Database? db;
    try {
      db = sqlite3.open(targetPath, mode: OpenMode.readOnly);
      db.execute('PRAGMA busy_timeout = 1000;');
      final tableCheck = db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'suite_settings' LIMIT 1;",
      );
      if (tableCheck.isEmpty) return 'dark';

      final rows = db.select(
        "SELECT value FROM suite_settings WHERE key = 'theme_mode' LIMIT 1;",
      );
      if (rows.isEmpty) return 'dark';
      final value = rows.first['value'] as String?;
      return value == 'light' ? 'light' : 'dark';
    } catch (_) {
      return 'dark';
    } finally {
      db?.close();
    }
  }
}
