import 'package:arp_scout/data/services/storage/arp_scout_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArpScoutPreferences Model Tests', () {
    test('default preferences have showAutoDetected=false and empty sets', () {
      const prefs = ArpScoutPreferences();
      expect(prefs.showAutoDetected, isFalse);
      expect(prefs.hiddenDeviceMacs, isEmpty);
      expect(prefs.explicitlyShownMacs, isEmpty);
      expect(prefs.selectedDeviceMacs, isEmpty);
    });

    test('toJson and fromJson serialize and deserialize correctly with normalized MACs', () {
      const original = ArpScoutPreferences(
        showAutoDetected: true,
        hiddenDeviceMacs: {'001122334455', 'AA:BB:CC:DD:EE:FF'},
        explicitlyShownMacs: {'112233445566'},
        selectedDeviceMacs: {'001122334455'},
      );

      final json = original.toJson();
      expect(json['showAutoDetected'], isTrue);
      expect(json['hiddenDeviceMacs'], isA<List>());
      expect(json['explicitlyShownMacs'], isA<List>());
      expect(json['selectedDeviceMacs'], isA<List>());

      final deserialized = ArpScoutPreferences.fromJson(json);
      expect(deserialized.showAutoDetected, isTrue);
      // Normalized MACs
      expect(deserialized.hiddenDeviceMacs, contains('00:11:22:33:44:55'));
      expect(deserialized.hiddenDeviceMacs, contains('AA:BB:CC:DD:EE:FF'));
      expect(deserialized.explicitlyShownMacs, contains('11:22:33:44:55:66'));
      expect(deserialized.selectedDeviceMacs, contains('00:11:22:33:44:55'));
    });

    test('copyWith creates modified instance preserving other fields', () {
      const prefs = ArpScoutPreferences(
        showAutoDetected: false,
        hiddenDeviceMacs: {'00:11:22:33:44:55'},
        explicitlyShownMacs: {'AA:BB:CC:DD:EE:FF'},
        selectedDeviceMacs: {'11:22:33:44:55:66'},
      );

      final updated = prefs.copyWith(showAutoDetected: true);
      expect(updated.showAutoDetected, isTrue);
      expect(updated.hiddenDeviceMacs, contains('00:11:22:33:44:55'));
      expect(updated.explicitlyShownMacs, contains('AA:BB:CC:DD:EE:FF'));
      expect(updated.selectedDeviceMacs, contains('11:22:33:44:55:66'));
    });
  });
}
