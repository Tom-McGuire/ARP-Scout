import 'package:arp_scout/data/services/storage/arp_scout_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArpScoutPreferences Model Tests', () {
    test('default preferences have showAutoDetected=false and empty hiddenDeviceMacs', () {
      const prefs = ArpScoutPreferences();
      expect(prefs.showAutoDetected, isFalse);
      expect(prefs.hiddenDeviceMacs, isEmpty);
    });

    test('toJson and fromJson serialize and deserialize correctly with normalized MACs', () {
      const original = ArpScoutPreferences(
        showAutoDetected: true,
        hiddenDeviceMacs: {'001122334455', 'AA:BB:CC:DD:EE:FF'},
      );

      final json = original.toJson();
      expect(json['showAutoDetected'], isTrue);
      expect(json['hiddenDeviceMacs'], isA<List>());

      final deserialized = ArpScoutPreferences.fromJson(json);
      expect(deserialized.showAutoDetected, isTrue);
      // Normalized MACs
      expect(deserialized.hiddenDeviceMacs, contains('00:11:22:33:44:55'));
      expect(deserialized.hiddenDeviceMacs, contains('AA:BB:CC:DD:EE:FF'));
    });

    test('copyWith creates modified instance preserving other fields', () {
      const prefs = ArpScoutPreferences(
        showAutoDetected: false,
        hiddenDeviceMacs: {'00:11:22:33:44:55'},
      );

      final updated = prefs.copyWith(showAutoDetected: true);
      expect(updated.showAutoDetected, isTrue);
      expect(updated.hiddenDeviceMacs, contains('00:11:22:33:44:55'));
    });
  });
}
