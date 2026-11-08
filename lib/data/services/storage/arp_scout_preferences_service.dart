import 'dart:convert';
import 'dart:io';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:path/path.dart' as p;

class ArpScoutPreferences {
  const ArpScoutPreferences({
    this.showAutoDetected = false,
    this.hiddenDeviceMacs = const {},
  });

  final bool showAutoDetected;
  final Set<String> hiddenDeviceMacs;

  ArpScoutPreferences copyWith({
    bool? showAutoDetected,
    Set<String>? hiddenDeviceMacs,
  }) {
    return ArpScoutPreferences(
      showAutoDetected: showAutoDetected ?? this.showAutoDetected,
      hiddenDeviceMacs: hiddenDeviceMacs ?? this.hiddenDeviceMacs,
    );
  }

  Map<String, dynamic> toJson() => {
        'showAutoDetected': showAutoDetected,
        'hiddenDeviceMacs': hiddenDeviceMacs.toList(),
      };

  factory ArpScoutPreferences.fromJson(Map<String, dynamic> json) {
    final showAuto = json['showAutoDetected'] as bool? ?? false;
    final hiddenList = json['hiddenDeviceMacs'] as List<dynamic>?;
    final hiddenSet = hiddenList != null
        ? hiddenList
            .whereType<String>()
            .map((m) => SharedDevice.normalizeMac(m))
            .toSet()
        : <String>{};
    return ArpScoutPreferences(
      showAutoDetected: showAuto,
      hiddenDeviceMacs: hiddenSet,
    );
  }
}

class ArpScoutPreferencesService {
  static const String preferencesFileName = 'arp_scout_prefs.json';

  static File getPreferencesFile() {
    final dir = SharedDeviceDatabase.getDefaultDirectoryPath();
    return File(p.join(dir, preferencesFileName));
  }

  static Future<ArpScoutPreferences> loadPreferences() async {
    try {
      final file = getPreferencesFile();
      if (!await file.exists()) {
        return const ArpScoutPreferences();
      }
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return ArpScoutPreferences.fromJson(json);
      }
    } catch (_) {}
    return const ArpScoutPreferences();
  }

  static Future<void> savePreferences(ArpScoutPreferences prefs) async {
    try {
      final file = getPreferencesFile();
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      await file.writeAsString(jsonEncode(prefs.toJson()));
    } catch (_) {}
  }
}
