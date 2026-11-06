import 'package:arp_scout/data/repositories/arp_repository.dart';
import 'package:arp_scout/domain/models/arp_filter.dart';
import 'package:arp_scout/domain/models/arp_host_record.dart';
import 'package:arp_scout/domain/models/host_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

void main() {
  group('ArpRepository Unit Tests', () {
    late ArpRepository repository;

    setUp(() async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
      repository = ArpRepository();
    });

    tearDown(() {
      repository.dispose();
    });

    test('getAvailableAdapters returns list of network interfaces', () async {
      final adapters = await repository.getAvailableAdapters();
      expect(adapters, isNotEmpty);
      expect(adapters.any((a) => a.name == 'All Interfaces (ARP Cache)'), isTrue);
    });

    test('syncWithSharedDevices registers new devices and infers categories', () {
      const record = ArpHostRecord(
        ipAddress: '192.168.1.15',
        ipNumeric: 3232235791,
        macAddress: '00:09:0F:11:22:33',
        vendor: 'Fortinet',
        hostname: 'fw-edge.local',
        subnet: '192.168.1.0/24',
        interfaceName: 'eth0',
        status: HostStatus.online,
        discoveryMethod: 'ARP',
        firstSeenMs: 1000,
        lastSeenMs: 2000,
      );

      final synced = repository.syncWithSharedDevices([record]);
      expect(synced.length, equals(1));

      // Device was registered into SharedDeviceDatabase
      final dev = SharedDeviceDatabase.instance.getDeviceByMac('00:09:0F:11:22:33');
      expect(dev, isNotNull);
      expect(dev!.name, equals('fw-edge.local'));
      expect(dev.vendor, equals('Fortinet'));
    });

    test('syncWithSharedDevices updates placeholder name during import if hostname exists', () {
      final normalizedMac = SharedDevice.normalizeMac('00:11:22:33:44:55');
      SharedDeviceDatabase.instance.upsertDevice(
        SharedDevice(
          macAddress: normalizedMac,
          name: 'Device $normalizedMac',
          vendor: 'Acme',
          deviceType: 'other',
          sourceApp: 'arp-scout',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final record = ArpHostRecord(
        ipAddress: '192.168.1.50',
        ipNumeric: 3232235826,
        macAddress: normalizedMac,
        vendor: 'Acme',
        hostname: 'fileserver-01',
        subnet: '192.168.1.0/24',
        interfaceName: 'eth0',
        status: HostStatus.online,
        discoveryMethod: 'ARP',
        firstSeenMs: 1000,
        lastSeenMs: 2000,
      );

      final synced = repository.syncWithSharedDevices([record], isImport: true);
      expect(synced.first.customName, equals('fileserver-01'));

      final dev = SharedDeviceDatabase.instance.getDeviceByMac(normalizedMac);
      expect(dev!.name, equals('fileserver-01'));
    });

    test('updateDeviceName creates new device in shared database when device did not exist', () {
      const mac = '00:1A:2B:99:88:77';
      repository.updateDeviceName(mac, 'New Production Switch');

      final dev = SharedDeviceDatabase.instance.getDeviceByMac(mac);
      expect(dev, isNotNull);
      expect(dev!.name, equals('New Production Switch'));
    });

    test('syncAllSharedDeviceNamesToLocalDb updates local database records from shared DB', () {
      repository.loadDemoTopology();
      final hosts = repository.queryHosts(filter: const ArpFilterCriteria());
      expect(hosts.isNotEmpty, isTrue);

      final targetHost = hosts.first;
      SharedDeviceDatabase.instance.updateDeviceName(targetHost.macAddress, 'Synchronized Switch');

      repository.syncAllSharedDeviceNamesToLocalDb();

      final reQueried = repository.queryHosts(filter: const ArpFilterCriteria());
      final match = reQueried.firstWhere((h) => h.macAddress == targetHost.macAddress);
      expect(match.customName, equals('Synchronized Switch'));
    });

    test('cleanupCancelledSweep and reconcileSweepCompletion delegate to database service', () {
      repository.loadDemoTopology();
      final total = repository.totalUnfilteredCount();
      expect(total, greaterThan(0));

      repository.cleanupCancelledSweep();
      // Should not crash and count remains valid
      expect(repository.totalUnfilteredCount(), equals(total));

      repository.reconcileSweepCompletion(
        subnet: '192.168.10.0/24',
        activeIps: {'192.168.10.1', '192.168.10.2'},
        markMissingAsStale: true,
      );

      final counts = repository.getStatusCounts();
      expect(counts[HostStatus.stale], greaterThan(0));
    });
  });
}
