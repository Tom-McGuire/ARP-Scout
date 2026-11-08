import 'package:arp_scout/domain/models/arp_filter.dart';
import 'package:arp_scout/domain/models/host_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArpFilterCriteria with Device Filtering', () {
    test('default criteria has no active filter', () {
      const criteria = ArpFilterCriteria();
      expect(criteria.hasActiveFilter, isFalse);
      expect(criteria.selectedDeviceMacs, isEmpty);
    });

    test('selecting device MACs marks hasActiveFilter as true', () {
      const criteria = ArpFilterCriteria(
        selectedDeviceMacs: {'00:11:22:33:44:55'},
      );
      expect(criteria.hasActiveFilter, isTrue);
      expect(criteria.selectedDeviceMacs.contains('00:11:22:33:44:55'), isTrue);
    });

    test('copyWith updates selectedDeviceMacs correctly', () {
      const criteria = ArpFilterCriteria(
        selectedStatuses: {HostStatus.online},
      );
      final updated = criteria.copyWith(
        selectedDeviceMacs: {'AA:BB:CC:DD:EE:FF'},
      );
      expect(updated.selectedStatuses, contains(HostStatus.online));
      expect(updated.selectedDeviceMacs, contains('AA:BB:CC:DD:EE:FF'));
      expect(updated.hasActiveFilter, isTrue);

      final cleared = updated.copyWith(selectedDeviceMacs: {});
      expect(cleared.selectedDeviceMacs, isEmpty);
      expect(cleared.hasActiveFilter, isTrue); // still has online status
    });
  });
}
