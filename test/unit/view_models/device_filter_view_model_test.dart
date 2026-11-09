import 'package:arp_scout/data/repositories/arp_repository.dart';
import 'package:arp_scout/data/services/database/arp_database_service.dart';
import 'package:arp_scout/domain/models/arp_host_record.dart';
import 'package:arp_scout/domain/models/host_status.dart';
import 'package:arp_scout/ui/features/scout/view_models/arp_scout_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

void main() {
  group('ArpScoutViewModel Device Filter & Auto-Detected Logic', () {
    late ArpDatabaseService db;
    late ArpRepository repository;
    late ArpScoutViewModel viewModel;

    setUp(() async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
      db = ArpDatabaseService();
      repository = ArpRepository(databaseService: db);

      // Seed SharedDeviceDatabase with a labeled device
      SharedDeviceDatabase.instance.upsertDevice(
        SharedDevice(
          macAddress: '00:1A:2B:3C:4D:5E',
          name: 'Core Router',
          deviceType: 'router',
          sourceApp: 'Test',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      // Seed another device with default un-named placeholder
      SharedDeviceDatabase.instance.upsertDevice(
        SharedDevice(
          macAddress: 'AA:BB:CC:DD:EE:FF',
          name: 'Device AA:BB:CC:DD:EE:FF',
          sourceApp: 'Test',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      // Seed hosts in ArpDatabaseService
      db.upsertBatch([
        ArpHostRecord(
          ipAddress: '192.168.1.1',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.1'),
          macAddress: '00:1A:2B:3C:4D:5E',
          vendor: 'Cisco',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.online,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
        ArpHostRecord(
          ipAddress: '192.168.1.50',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.50'),
          macAddress: '11:22:33:44:55:66',
          vendor: 'Raspberry Pi',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.online,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
      ]);

      viewModel = ArpScoutViewModel(repository: repository);
      await Future.delayed(const Duration(milliseconds: 30));
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('visibleSharedDevices contains only labeled devices with custom names and not hidden', () {
      expect(viewModel.visibleSharedDevices.length, equals(1));
      expect(viewModel.visibleSharedDevices.first.name, equals('Core Router'));
      expect(viewModel.visibleSharedDevices.first.macAddress, equals('00:1A:2B:3C:4D:5E'));
    });

    test('autoDetectedUnlabeledHosts only returns unlabeled hosts when showAutoDetected is true', () {
      // By default showAutoDetected is false
      viewModel.setShowAutoDetected(false);
      expect(viewModel.autoDetectedUnlabeledHosts, isEmpty);

      // Turn on showAutoDetected
      viewModel.setShowAutoDetected(true);
      expect(viewModel.autoDetectedUnlabeledHosts.length, equals(1));
      expect(viewModel.autoDetectedUnlabeledHosts.first.macAddress, equals('11:22:33:44:55:66'));
      expect(viewModel.autoDetectedUnlabeledHosts.first.ipAddress, equals('192.168.1.50'));
    });

    test('toggleDeviceVisibility hides and reveals devices in visibleSharedDevices', () {
      expect(viewModel.visibleSharedDevices.length, equals(1));

      // Hide Core Router
      viewModel.toggleDeviceVisibility('00:1A:2B:3C:4D:5E');
      expect(viewModel.visibleSharedDevices, isEmpty);
      expect(viewModel.hiddenDeviceMacs, contains('00:1A:2B:3C:4D:5E'));

      // Unhide Core Router
      viewModel.toggleDeviceVisibility('00:1A:2B:3C:4D:5E');
      expect(viewModel.visibleSharedDevices.length, equals(1));
      expect(viewModel.hiddenDeviceMacs, isNot(contains('00:1A:2B:3C:4D:5E')));
    });

    test('toggleDevicePill toggles device filter and updates host queries', () {
      expect(viewModel.filter.selectedDeviceMacs, isEmpty);
      expect(viewModel.hosts.length, equals(2));

      // Select Core Router
      viewModel.toggleDevicePill('00:1A:2B:3C:4D:5E');
      expect(viewModel.filter.selectedDeviceMacs, contains('00:1A:2B:3C:4D:5E'));
      expect(viewModel.hosts.length, equals(1));
      expect(viewModel.hosts.first.ipAddress, equals('192.168.1.1'));

      // Deselect Core Router
      viewModel.toggleDevicePill('00:1A:2B:3C:4D:5E');
      expect(viewModel.filter.selectedDeviceMacs, isEmpty);
      expect(viewModel.hosts.length, equals(2));
    });

    test('allKnownCustomDevices and allUnknownDevices correctly separate labeled and unlabeled devices', () {
      final known = viewModel.allKnownCustomDevices;
      expect(known.length, equals(1));
      expect(known.first.name, equals('Core Router'));

      final unknown = viewModel.allUnknownDevices;
      // AA:BB:CC:DD:EE:FF from DB (unnamed) + 11:22:33:44:55:66 from ARP table
      expect(unknown.length, equals(2));
      final unknownMacs = unknown.map((u) => u.macAddress).toSet();
      expect(unknownMacs, contains('AA:BB:CC:DD:EE:FF'));
      expect(unknownMacs, contains('11:22:33:44:55:66'));
    });

    test('explicitly unhiding an unknown device shows it even when showAutoDetected is false', () {
      viewModel.setShowAutoDetected(false);
      expect(viewModel.autoDetectedUnlabeledHosts, isEmpty);

      // Unhide the unknown ARP host (11:22:33:44:55:66)
      viewModel.toggleDeviceVisibility('11:22:33:44:55:66');
      expect(viewModel.explicitlyShownMacs, contains('11:22:33:44:55:66'));
      expect(viewModel.autoDetectedUnlabeledHosts.length, equals(1));
      expect(viewModel.autoDetectedUnlabeledHosts.first.macAddress, equals('11:22:33:44:55:66'));

      // Hide it again
      viewModel.toggleDeviceVisibility('11:22:33:44:55:66');
      expect(viewModel.explicitlyShownMacs, isNot(contains('11:22:33:44:55:66')));
      expect(viewModel.autoDetectedUnlabeledHosts, isEmpty);
    });

    test('unhideAllDevices resets all overrides and enables showAutoDetected', () {
      viewModel.setDeviceHidden('00:1A:2B:3C:4D:5E', true);
      viewModel.toggleDeviceVisibility('11:22:33:44:55:66');
      viewModel.setShowAutoDetected(false);

      expect(viewModel.hiddenDeviceMacs, contains('00:1A:2B:3C:4D:5E'));

      viewModel.unhideAllDevices();
      expect(viewModel.hiddenDeviceMacs, isEmpty);
      expect(viewModel.explicitlyShownMacs, isEmpty);
      expect(viewModel.showAutoDetected, isTrue);
    });

    test('interdependent combined counts: selecting status updates device counts', () {
      // Both hosts are online
      expect(viewModel.deviceCounts['00:1A:2B:3C:4D:5E'], equals(1));
      expect(viewModel.deviceCounts['11:22:33:44:55:66'], equals(1));

      // Filter by conflict status (neither is in conflict)
      viewModel.toggleStatus(HostStatus.conflict);
      expect(viewModel.deviceCounts['00:1A:2B:3C:4D:5E'] ?? 0, equals(0));
      expect(viewModel.deviceCounts['11:22:33:44:55:66'] ?? 0, equals(0));

      // Filter by online status
      viewModel.toggleStatus(HostStatus.conflict); // unselect conflict
      viewModel.toggleStatus(HostStatus.online);
      expect(viewModel.deviceCounts['00:1A:2B:3C:4D:5E'], equals(1));
      expect(viewModel.deviceCounts['11:22:33:44:55:66'], equals(1));
    });
  });
}
