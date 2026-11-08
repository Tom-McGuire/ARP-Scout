import 'package:arp_scout/data/services/database/arp_database_service.dart';
import 'package:arp_scout/domain/models/arp_filter.dart';
import 'package:arp_scout/domain/models/arp_host_record.dart';
import 'package:arp_scout/domain/models/host_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArpDatabaseService Device & Status Combined Filtering', () {
    late ArpDatabaseService db;

    setUp(() {
      db = ArpDatabaseService();
    });

    tearDown(() {
      db.close();
    });

    test('getDeviceHostCounts accurately counts hosts per MAC respecting active status filters', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final hosts = [
        // Device A (00:11:22:33:44:01) has 2 online hosts and 1 stale host
        ArpHostRecord(
          ipAddress: '192.168.1.10',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.10'),
          macAddress: '00:11:22:33:44:01',
          vendor: 'Cisco',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.online,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
        ArpHostRecord(
          ipAddress: '192.168.1.11',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.11'),
          macAddress: '00:11:22:33:44:01',
          vendor: 'Cisco',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.online,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
        ArpHostRecord(
          ipAddress: '192.168.1.12',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.12'),
          macAddress: '00:11:22:33:44:01',
          vendor: 'Cisco',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.stale,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),

        // Device B (00:AA:BB:CC:DD:02) has 1 conflict host
        ArpHostRecord(
          ipAddress: '192.168.1.20',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.20'),
          macAddress: '00:AA:BB:CC:DD:02',
          vendor: 'Apple',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.conflict,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
      ];

      db.upsertBatch(hosts);

      // Unfiltered device counts
      final allDeviceCounts = db.getDeviceHostCounts();
      expect(allDeviceCounts['00:11:22:33:44:01'], equals(3));
      expect(allDeviceCounts['00:AA:BB:CC:DD:02'], equals(1));

      // With status filter: only Online hosts
      const onlineFilter = ArpFilterCriteria(
        selectedStatuses: {HostStatus.online},
      );
      final onlineDeviceCounts = db.getDeviceHostCounts(onlineFilter);
      // Device A has 2 online hosts
      expect(onlineDeviceCounts['00:11:22:33:44:01'], equals(2));
      // Device B has 0 online hosts
      expect(onlineDeviceCounts['00:AA:BB:CC:DD:02'] ?? 0, equals(0));

      // With status filter: only Conflict hosts
      const conflictFilter = ArpFilterCriteria(
        selectedStatuses: {HostStatus.conflict},
      );
      final conflictDeviceCounts = db.getDeviceHostCounts(conflictFilter);
      expect(conflictDeviceCounts['00:11:22:33:44:01'] ?? 0, equals(0));
      expect(conflictDeviceCounts['00:AA:BB:CC:DD:02'], equals(1));
    });

    test('getStatusCounts calculates status counts respecting active device filters', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final hosts = [
        ArpHostRecord(
          ipAddress: '192.168.1.10',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.10'),
          macAddress: '00:11:22:33:44:01',
          vendor: 'Cisco',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.online,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
        ArpHostRecord(
          ipAddress: '192.168.1.20',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.20'),
          macAddress: '00:AA:BB:CC:DD:02',
          vendor: 'Apple',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.conflict,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
      ];

      db.upsertBatch(hosts);

      // Total unfiltered status counts
      final totalCounts = db.getStatusCounts();
      expect(totalCounts[HostStatus.online], equals(1));
      expect(totalCounts[HostStatus.conflict], equals(1));

      // Filter by Device A only: Status triage counts for Device A only
      const deviceAFilter = ArpFilterCriteria(
        selectedDeviceMacs: {'00:11:22:33:44:01'},
      );
      final deviceACounts = db.getStatusCounts(deviceAFilter);
      expect(deviceACounts[HostStatus.online], equals(1));
      expect(deviceACounts[HostStatus.conflict], equals(0));
    });

    test('queryHosts filters rows matching selectedDeviceMacs', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final hosts = [
        ArpHostRecord(
          ipAddress: '192.168.1.10',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.10'),
          macAddress: '00:11:22:33:44:01',
          vendor: 'Cisco',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.online,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
        ArpHostRecord(
          ipAddress: '192.168.1.20',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.20'),
          macAddress: '00:AA:BB:CC:DD:02',
          vendor: 'Apple',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.conflict,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
      ];

      db.upsertBatch(hosts);

      final results = db.queryHosts(
        offset: 0,
        limit: 10,
        filter: const ArpFilterCriteria(
          selectedDeviceMacs: {'00:AA:BB:CC:DD:02'},
        ),
      );

      expect(results.length, equals(1));
      expect(results.first.ipAddress, equals('192.168.1.20'));
      expect(results.first.macAddress, equals('00:AA:BB:CC:DD:02'));
    });
  });
}
