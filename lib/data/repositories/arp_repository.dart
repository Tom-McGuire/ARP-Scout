import 'package:flutter/foundation.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../domain/models/arp_filter.dart';
import '../../domain/models/arp_host_record.dart';
import '../../domain/models/host_status.dart';
import '../../domain/models/network_adapter_info.dart';
import '../services/database/arp_database_service.dart';
import '../services/export/export_service.dart';
import '../services/generator/demo_arp_generator.dart';
import '../services/import/csv_import_service.dart';
import '../services/network/network_adapter_service.dart';
import '../services/scanner/subnet_scanner_service.dart';

class ArpRepository {
  ArpRepository({
    ArpDatabaseService? databaseService,
    SubnetScannerService? scannerService,
  }) : _dbService = databaseService ?? ArpDatabaseService(),
       _scannerService = scannerService ?? SubnetScannerService();

  final ArpDatabaseService _dbService;
  final SubnetScannerService _scannerService;

  ArpDatabaseService get dbService => _dbService;
  SubnetScannerService get scannerService => _scannerService;

  Future<List<NetworkAdapterInfo>> getAvailableAdapters() {
    return NetworkAdapterService.getAvailableAdapters();
  }

  /// Syncs newly discovered records with the Network Suite cross-process device database.
  /// Decorates existing records with their persistent custom name or registers newly discovered MACs.
  List<ArpHostRecord> syncWithSharedDevices(List<ArpHostRecord> records) {
    if (records.isEmpty) return records;
    final results = List<ArpHostRecord>.from(records);

    for (var i = 0; i < results.length; i++) {
      final record = results[i];
      final rawMac = record.macAddress;
      if (!SharedDevice.isValidMac(rawMac)) continue;

      final normalizedMac = SharedDevice.normalizeMac(rawMac);
      try {
        if (SharedDeviceDatabase.instance.isInitialized) {
          final existing = SharedDeviceDatabase.instance.getDeviceByMac(normalizedMac);
          if (existing != null) {
            results[i] = record.copyWith(customName: existing.name);
          } else {
            // Register newly discovered device into SharedDeviceDatabase
            final vendor = record.vendor.isNotEmpty && record.vendor != 'Unknown Vendor'
                ? record.vendor
                : OuiLookup.lookupVendor(normalizedMac);
            final hostname = record.hostname ?? '';
            final category = OuiLookup.inferCategory(vendor, hostname);
            final device = SharedDevice(
              macAddress: normalizedMac,
              name: hostname.isNotEmpty ? hostname : 'Device $normalizedMac',
              vendor: vendor,
              deviceType: category.key,
              notes: 'Discovered by arp-scout (${record.ipAddress})',
              sourceApp: 'arp-scout',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
            SharedDeviceDatabase.instance.upsertDevice(device);
            results[i] = record.copyWith(customName: device.name);
          }
        }
      } catch (e) {
        debugPrint('Shared device sync error: $e');
      }
    }

    return results;
  }

  /// Updates friendly device name both in the cross-process SharedDeviceDatabase
  /// and within the local in-memory SQLite state.
  void updateDeviceName(String macAddress, String newName) {
    if (!SharedDevice.isValidMac(macAddress)) return;
    final normalizedMac = SharedDevice.normalizeMac(macAddress);
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) return;

    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        final existing = SharedDeviceDatabase.instance.getDeviceByMac(normalizedMac);
        if (existing != null) {
          SharedDeviceDatabase.instance.updateDeviceName(normalizedMac, trimmedName);
        } else {
          final vendor = OuiLookup.lookupVendor(normalizedMac);
          final category = OuiLookup.inferCategory(vendor, trimmedName);
          SharedDeviceDatabase.instance.upsertDevice(
            SharedDevice(
              macAddress: normalizedMac,
              name: trimmedName,
              vendor: vendor,
              deviceType: category.key,
              notes: 'Registered by arp-scout',
              sourceApp: 'arp-scout',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating device name in shared database: $e');
    }

    _dbService.updateCustomNameByMac(normalizedMac, trimmedName);
  }

  /// Synchronizes all known device names from SharedDeviceDatabase into the local SQLite table.
  void syncAllSharedDeviceNamesToLocalDb() {
    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        final devices = SharedDeviceDatabase.instance.getAllDevices();
        for (final dev in devices) {
          _dbService.updateCustomNameByMac(dev.macAddress, dev.name);
        }
      }
    } catch (e) {
      debugPrint('Error syncing shared device names: $e');
    }
  }

  void upsertBatch(List<ArpHostRecord> records) {
    final synced = syncWithSharedDevices(records);
    _dbService.upsertBatch(synced);
  }

  void cleanupCancelledSweep() {
    _dbService.cleanupCancelledSweep();
  }

  void reconcileSweepCompletion({
    required String subnet,
    required Set<String> activeIps,
    bool markMissingAsStale = true,
  }) {
    _dbService.reconcileSweepCompletion(
      subnet: subnet,
      activeIps: activeIps,
      markMissingAsStale: markMissingAsStale,
    );
  }

  List<ArpHostRecord> queryHosts({
    int offset = 0,
    int limit = 500,
    required ArpFilterCriteria filter,
  }) {
    return _dbService.queryHosts(
      offset: offset,
      limit: limit,
      filter: filter,
    );
  }

  int countHosts(ArpFilterCriteria filter) {
    return _dbService.countHosts(filter);
  }

  int totalUnfilteredCount() {
    return _dbService.totalUnfilteredCount();
  }

  Map<HostStatus, int> getStatusCounts() {
    return _dbService.getStatusCounts();
  }

  void clearAll() {
    _dbService.clearAll();
  }

  void loadDemoTopology({String subnetCidr = '192.168.10.0/24'}) {
    final demoRecords = DemoArpGenerator.generateEnterpriseSubnet(
      subnetCidr: subnetCidr,
    );
    upsertBatch(demoRecords);
  }

  Future<List<ArpHostRecord>> performSubnetSweep({
    required String targetSubnet,
    required String interfaceName,
    String? localInterfaceIp,
    bool arpCacheOnly = false,
    void Function(int probed, int total, String phase, List<ArpHostRecord> partialBatch)?
    onProgress,
  }) {
    return _scannerService.performSubnetSweep(
      targetSubnet: targetSubnet,
      interfaceName: interfaceName,
      localInterfaceIp: localInterfaceIp,
      arpCacheOnly: arpCacheOnly,
      onProgress: onProgress,
    );
  }

  Future<void> cancelActiveScan() {
    return _scannerService.cancelActiveScan();
  }

  Future<CsvImportResult?> importCsvFile({bool replaceExisting = false}) async {
    final result = await CsvImportService.pickAndParseCsv();
    if (result == null) return null;
    if (replaceExisting) {
      _dbService.clearAll();
    }
    upsertBatch(result.records);
    return result;
  }

  Future<String?> exportCsv(ArpFilterCriteria filter) {
    final allMatching = _dbService.queryHosts(
      offset: 0,
      limit: 100000,
      filter: filter,
    );
    return ExportService.exportToCsv(allMatching);
  }

  Future<String?> exportJson(ArpFilterCriteria filter) {
    final allMatching = _dbService.queryHosts(
      offset: 0,
      limit: 100000,
      filter: filter,
    );
    return ExportService.exportToJson(allMatching);
  }

  void dispose() {
    _scannerService.cancelActiveScan();
    _dbService.close();
  }
}
