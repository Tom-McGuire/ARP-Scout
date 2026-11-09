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

  /// Syncs newly discovered or imported records with the Network Suite cross-process device database.
  /// Decorates existing records with their persistent custom name or registers newly discovered MACs.
  /// When [isImport] is true, records with custom names will update the SharedDeviceDatabase.
  List<ArpHostRecord> syncWithSharedDevices(
    List<ArpHostRecord> records, {
    bool isImport = false,
    bool isDemo = false,
  }) {
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
          final hasExplicitCustomName = record.customName != null && record.customName!.trim().isNotEmpty;
          final trimmedCustomName = hasExplicitCustomName ? record.customName!.trim() : null;

          if (isImport && trimmedCustomName != null) {
            // During import, an explicitly specified custom name MUST update the shared devices database.
            if (!isDemo) {
              if (existing != null) {
                SharedDeviceDatabase.instance.updateDeviceName(normalizedMac, trimmedCustomName);
              } else {
                final vendor = record.vendor.isNotEmpty && record.vendor != 'Unknown Vendor'
                    ? record.vendor
                    : OuiLookup.lookupVendor(normalizedMac);
                final category = OuiLookup.inferCategory(vendor, trimmedCustomName);
                SharedDeviceDatabase.instance.upsertDevice(
                  SharedDevice(
                    macAddress: normalizedMac,
                    name: trimmedCustomName,
                    vendor: vendor,
                    deviceType: category.key,
                    notes: 'Imported by arp-scout (${record.ipAddress})',
                    sourceApp: 'arp-scout',
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
                );
              }
            }
            results[i] = record.copyWith(customName: trimmedCustomName);
          } else if (existing != null) {
            // If importing and existing device only had a placeholder 'Device AA:BB:...' name,
            // update it if the imported record has a real hostname.
            if (isImport &&
                !isDemo &&
                existing.name == 'Device $normalizedMac' &&
                record.hostname != null &&
                record.hostname!.trim().isNotEmpty) {
              final hostName = record.hostname!.trim();
              SharedDeviceDatabase.instance.updateDeviceName(normalizedMac, hostName);
              results[i] = record.copyWith(customName: hostName);
            } else {
              results[i] = record.copyWith(customName: existing.name);
            }
          } else {
            // Register newly discovered or imported device into SharedDeviceDatabase (skipped for demo data)
            final nameCandidate = trimmedCustomName ??
                (record.hostname != null && record.hostname!.trim().isNotEmpty
                    ? record.hostname!.trim()
                    : 'Device $normalizedMac');

            if (!isDemo) {
              final vendor = record.vendor.isNotEmpty && record.vendor != 'Unknown Vendor'
                  ? record.vendor
                  : OuiLookup.lookupVendor(normalizedMac);
              final category = OuiLookup.inferCategory(vendor, nameCandidate);
              final device = SharedDevice(
                macAddress: normalizedMac,
                name: nameCandidate,
                vendor: vendor,
                deviceType: category.key,
                notes: isImport
                    ? 'Imported by arp-scout (${record.ipAddress})'
                    : 'Discovered by arp-scout (${record.ipAddress})',
                sourceApp: 'arp-scout',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              );
              SharedDeviceDatabase.instance.upsertDevice(device);
              results[i] = record.copyWith(customName: device.name);
            } else {
              results[i] = record.copyWith(customName: nameCandidate);
            }
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

  void upsertBatch(List<ArpHostRecord> records, {bool isImport = false, bool isDemo = false}) {
    final synced = syncWithSharedDevices(records, isImport: isImport, isDemo: isDemo);
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

  Map<HostStatus, int> getStatusCounts([ArpFilterCriteria? filter]) {
    return _dbService.getStatusCounts(filter);
  }

  Map<String, int> getDeviceHostCounts([ArpFilterCriteria? filter]) {
    return _dbService.getDeviceHostCounts(filter);
  }

  List<SharedDevice> getAllSharedDevices() {
    if (SharedDeviceDatabase.instance.isInitialized) {
      return SharedDeviceDatabase.instance.getAllDevices();
    }
    return [];
  }

  void updateDeviceDetails({
    required String macAddress,
    required String name,
    String? deviceType,
    String? vendor,
    String? notes,
  }) {
    if (!SharedDevice.isValidMac(macAddress)) return;
    final normalizedMac = SharedDevice.normalizeMac(macAddress);
    final trimmedName = name.trim();

    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        final existing = SharedDeviceDatabase.instance.getDeviceByMac(normalizedMac);
        if (existing != null) {
          SharedDeviceDatabase.instance.updateDeviceDetails(
            normalizedMac,
            name: trimmedName.isNotEmpty ? trimmedName : null,
            deviceType: deviceType,
            vendor: vendor,
            notes: notes,
          );
        } else {
          SharedDeviceDatabase.instance.upsertDevice(
            SharedDevice(
              macAddress: normalizedMac,
              name: trimmedName.isNotEmpty ? trimmedName : 'Device $normalizedMac',
              deviceType: deviceType,
              vendor: vendor,
              notes: notes,
              sourceApp: 'ARP-Scout',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        }
      }
    } catch (_) {}

    _dbService.updateCustomNameByMac(normalizedMac, trimmedName);
  }

  void clearAll() {
    _dbService.clearAll();
  }

  void loadDemoTopology({String subnetCidr = '192.168.10.0/24'}) {
    final demoRecords = DemoArpGenerator.generateEnterpriseSubnet(
      subnetCidr: subnetCidr,
    );
    upsertBatch(demoRecords, isDemo: true);
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
    upsertBatch(result.records, isImport: true);
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
