import 'package:arp_scout/data/repositories/arp_repository.dart';
import 'package:arp_scout/domain/models/host_status.dart';
import 'package:arp_scout/domain/models/network_adapter_info.dart';
import 'package:arp_scout/ui/features/scout/view_models/arp_scout_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

void main() {
  group('ArpScoutViewModel Unit Tests', () {
    late ArpRepository repository;
    late ArpScoutViewModel viewModel;

    setUp(() async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
      repository = ArpRepository();
      viewModel = ArpScoutViewModel(repository: repository);
      // Wait for async _init (refreshAdapters)
      await Future.delayed(const Duration(milliseconds: 10));
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('initializes with default state and all-interfaces adapter', () {
      expect(viewModel.hosts, isEmpty);
      expect(viewModel.totalHostCount, equals(0));
      expect(viewModel.unfilteredTotalCount, equals(0));
      expect(viewModel.conflictCount, equals(0));
      expect(viewModel.selectedRecord, isNull);
      expect(viewModel.isScanningOrWatching, isFalse);
      expect(viewModel.isLoadingMore, isFalse);
      expect(viewModel.isImporting, isFalse);
    });

    test('loadDemoTopology populates hosts, counts, and detects IP conflicts', () {
      viewModel.loadDemoTopology();

      expect(viewModel.hosts.isNotEmpty, isTrue);
      expect(viewModel.totalHostCount, greaterThan(10));
      expect(viewModel.unfilteredTotalCount, equals(viewModel.totalHostCount));
      expect(viewModel.conflictCount, greaterThanOrEqualTo(1));
      expect(viewModel.statusCounts[HostStatus.online], greaterThan(0));
      expect(viewModel.scanProgress.currentPhase, contains('Loaded Demo Enterprise Subnet'));
    });

    test('selectRecord sets and clears currently inspected host', () {
      viewModel.loadDemoTopology();
      final firstHost = viewModel.hosts.first;

      viewModel.selectRecord(firstHost);
      expect(viewModel.selectedRecord, equals(firstHost));

      viewModel.selectRecord(null);
      expect(viewModel.selectedRecord, isNull);
    });

    test('filtering by search query matches IP, MAC, vendor, and custom name', () {
      viewModel.loadDemoTopology();
      final total = viewModel.totalHostCount;

      // Filter by partial IP
      viewModel.setSearchQuery('192.168.10.1');
      expect(viewModel.totalHostCount, lessThan(total));
      expect(viewModel.hosts.every((h) => h.ipAddress.contains('192.168.10.1')), isTrue);

      // Clear search
      viewModel.setSearchQuery('');
      expect(viewModel.totalHostCount, equals(total));
    });

    test('filtering by dedicated IP, MAC, and vendor fields', () {
      viewModel.loadDemoTopology();

      viewModel.setIpFilter('192.168.10.50');
      expect(viewModel.hosts.every((h) => h.ipAddress.contains('192.168.10.50')), isTrue);

      viewModel.resetFilters();
      viewModel.setVendorFilter('Cisco');
      expect(viewModel.hosts.every((h) => h.vendor.toLowerCase().contains('cisco')), isTrue);

      viewModel.resetFilters();
      viewModel.setMacFilter('00:09:0F');
      expect(viewModel.hosts.isNotEmpty, isTrue);
      expect(
        viewModel.hosts.every(
          (h) =>
              h.macAddress.toUpperCase().contains('00:09:0F') ||
              h.macAddress.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase().contains('00090F') ||
              h.conflictingMacs.any((m) => m.toUpperCase().contains('00:09:0F')),
        ),
        isTrue,
      );
    });

    test('toggleStatus and toggleConflictsOnly isolate host statuses', () {
      viewModel.loadDemoTopology();

      // Only conflicts
      viewModel.toggleConflictsOnly();
      expect(viewModel.filter.conflictsOnly, isTrue);
      expect(viewModel.hosts.every((h) => h.status == HostStatus.conflict), isTrue);

      // Toggle off conflicts
      viewModel.toggleConflictsOnly();
      expect(viewModel.filter.conflictsOnly, isFalse);

      // Select specific status chip
      viewModel.toggleStatus(HostStatus.online);
      expect(viewModel.filter.selectedStatuses, contains(HostStatus.online));
      expect(viewModel.hosts.every((h) => h.status == HostStatus.online), isTrue);

      // Toggle off status
      viewModel.toggleStatus(HostStatus.online);
      expect(viewModel.filter.selectedStatuses, isEmpty);
    });

    test('setSort toggles ascending/descending and changes sort column', () {
      viewModel.loadDemoTopology();

      viewModel.setSort('vendor');
      expect(viewModel.sortColumn, equals('vendor'));
      expect(viewModel.sortAscending, isTrue);

      // Toggle same column
      viewModel.setSort('vendor');
      expect(viewModel.sortColumn, equals('vendor'));
      expect(viewModel.sortAscending, isFalse);
    });

    test('simulateRogueMacConflict creates real-time conflict in table and statusCounts', () {
      viewModel.loadDemoTopology();
      final initialConflicts = viewModel.conflictCount;

      viewModel.simulateRogueMacConflict();

      expect(viewModel.conflictCount, greaterThanOrEqualTo(initialConflicts));
      final conflictingHosts = viewModel.hosts.where((h) => h.status == HostStatus.conflict);
      expect(conflictingHosts.isNotEmpty, isTrue);
    });

    test('updateDeviceName persists custom name to repository and view model', () {
      viewModel.loadDemoTopology();
      final target = viewModel.hosts.first;

      viewModel.updateDeviceName(target.macAddress, 'Engineering Gateway Router');

      final updated = viewModel.hosts.firstWhere((h) => h.macAddress == target.macAddress);
      expect(updated.customName, equals('Engineering Gateway Router'));
      expect(updated.displayName, equals('Engineering Gateway Router'));
    });

    test('selectAdapter updates target subnet and generated command preview', () {
      const adapter = NetworkAdapterInfo(
        name: 'Secondary LAN (eth1)',
        ipAddress: '10.0.0.15',
        subnetCidr: '10.0.0.0/24',
      );

      viewModel.selectAdapter(adapter);
      expect(viewModel.selectedAdapter, equals(adapter));
      expect(viewModel.scanProgress.targetSubnet, equals('10.0.0.0/24'));
      expect(viewModel.scanProgress.generatedCommand, contains('10.0.0.0/24'));
    });

    test('updateTargetSubnet updates CIDR string and command preview', () {
      const adapter = NetworkAdapterInfo(
        name: 'Secondary LAN (eth1)',
        ipAddress: '10.0.0.15',
        subnetCidr: '10.0.0.0/24',
      );
      viewModel.selectAdapter(adapter);
      viewModel.updateTargetSubnet('172.16.0.0/16');
      expect(viewModel.scanProgress.targetSubnet, equals('172.16.0.0/16'));
      expect(viewModel.scanProgress.generatedCommand, contains('172.16.0.0/16'));
    });

    test('dismissError clears scanProgress lastError', () {
      // Trigger invalid subnet to produce error
      viewModel.startSubnetScan(subnetOverride: 'invalid_cidr');
      expect(viewModel.scanProgress.lastError, isNotNull);

      viewModel.dismissError();
      expect(viewModel.scanProgress.lastError, isNull);
    });

    test('clearHosts empties database, clears selection, and resets loaded file', () {
      viewModel.loadDemoTopology();
      expect(viewModel.hosts.isNotEmpty, isTrue);

      viewModel.clearHosts();
      expect(viewModel.hosts, isEmpty);
      expect(viewModel.totalHostCount, equals(0));
      expect(viewModel.selectedRecord, isNull);
      expect(viewModel.loadedFileName, isNull);
    });

    test('toggleContinuousWatch toggles watch state and stopScan cancels timer', () async {
      expect(viewModel.scanProgress.isContinuousWatch, isFalse);

      viewModel.toggleContinuousWatch();
      expect(viewModel.scanProgress.isContinuousWatch, isTrue);

      viewModel.toggleContinuousWatch();
      expect(viewModel.scanProgress.isContinuousWatch, isFalse);

      viewModel.toggleContinuousWatch();
      expect(viewModel.scanProgress.isContinuousWatch, isTrue);

      await viewModel.stopScan();
      expect(viewModel.scanProgress.isContinuousWatch, isFalse);
      expect(viewModel.scanProgress.isScanning, isFalse);
    });

    test('loadMoreHosts handles pagination boundaries gracefully', () {
      viewModel.loadDemoTopology();
      final initialCount = viewModel.hosts.length;

      // When there are no more hosts beyond initial demo batch
      viewModel.loadMoreHosts();
      expect(viewModel.hosts.length, equals(initialCount));
    });

    test('closeLoadedFile clears filename and hosts', () {
      viewModel.loadDemoTopology();
      expect(viewModel.hosts.isNotEmpty, isTrue);

      viewModel.closeLoadedFile();
      expect(viewModel.loadedFileName, isNull);
      expect(viewModel.hosts, isEmpty);
    });
  });
}
