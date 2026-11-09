import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../../../data/repositories/arp_repository.dart';
import '../../../../data/services/import/csv_import_service.dart';
import '../../../../data/services/oui/oui_lookup_service.dart';
import '../../../../data/services/scanner/subnet_scanner_service.dart';
import '../../../../data/services/storage/arp_scout_preferences_service.dart';
import '../../../../domain/models/arp_filter.dart';
import '../../../../domain/models/arp_host_record.dart';
import '../../../../domain/models/host_status.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../../../../domain/models/scan_progress.dart';
import '../../../../domain/models/unknown_device_entry.dart';

class ArpScoutViewModel extends ChangeNotifier {
  ArpScoutViewModel({
    ArpRepository? repository,
    this.initialSubnet,
    this.initialAdapterIp,
    this.initialAdapterName,
    bool autoStart = false,
  })  : initialAutoStart = autoStart,
        _repository = repository ?? ArpRepository() {
    _init();
  }

  final ArpRepository _repository;
  final String? initialSubnet;
  final String? initialAdapterIp;
  final String? initialAdapterName;
  final bool initialAutoStart;
  static const int pageSize = 500;

  List<NetworkAdapterInfo> _adapters = [NetworkAdapterInfo.all];
  NetworkAdapterInfo _selectedAdapter = NetworkAdapterInfo.all;
  ArpFilterCriteria _filter = const ArpFilterCriteria();
  ScanProgress _scanProgress = const ScanProgress();
  List<ArpHostRecord> _hosts = [];
  Map<HostStatus, int> _statusCounts = {
    for (final s in HostStatus.values) s: 0,
  };
  int _totalHostCount = 0;
  int _unfilteredTotalCount = 0;
  bool _isLoadingMore = false;
  bool _isImporting = false;
  String? _loadedFileName;
  ArpHostRecord? _selectedRecord;
  Timer? _watchTimer;
  StreamSubscription<void>? _sharedDbSubscription;
  bool _isDisposed = false;

  bool _showAutoDetected = false;
  Set<String> _hiddenDeviceMacs = {};
  Set<String> _explicitlyShownMacs = {};
  Map<String, int> _deviceCounts = {};

  List<NetworkAdapterInfo> get adapters => _adapters;
  NetworkAdapterInfo get selectedAdapter => _selectedAdapter;
  ArpFilterCriteria get filter => _filter;
  ScanProgress get scanProgress => _scanProgress;
  List<ArpHostRecord> get hosts => _hosts;
  Map<HostStatus, int> get statusCounts => _statusCounts;
  Map<String, int> get deviceCounts => _deviceCounts;
  int get totalHostCount => _totalHostCount;
  int get unfilteredTotalCount => _unfilteredTotalCount;
  int get conflictCount => _statusCounts[HostStatus.conflict] ?? 0;
  bool get hasMoreHosts => _hosts.length < _totalHostCount;
  bool get isLoadingMore => _isLoadingMore;
  bool get isImporting => _isImporting;
  String? get loadedFileName => _loadedFileName;
  ArpHostRecord? get selectedRecord => _selectedRecord;
  String get sortColumn => _filter.sortColumn;
  bool get sortAscending => _filter.sortAscending;
  bool get isScanningOrWatching =>
      _scanProgress.isScanning || _scanProgress.isContinuousWatch;

  bool get showAutoDetected => _showAutoDetected;
  Set<String> get hiddenDeviceMacs => _hiddenDeviceMacs;
  Set<String> get explicitlyShownMacs => _explicitlyShownMacs;

  /// Known devices from SharedDeviceDatabase that have been given a custom name
  List<SharedDevice> get allKnownCustomDevices {
    if (!SharedDeviceDatabase.instance.isInitialized) return const [];
    try {
      return SharedDeviceDatabase.instance
          .getAllDevices(hideDefaultNamed: true);
    } catch (_) {
      return const [];
    }
  }

  /// Returns all labeled devices from SharedDeviceDatabase that are not hidden in ARP Scout.
  List<SharedDevice> get visibleSharedDevices {
    if (!SharedDeviceDatabase.instance.isInitialized) return const [];
    try {
      final all = SharedDeviceDatabase.instance.getAllDevices(hideDefaultNamed: true);
      return all.where((d) => !_hiddenDeviceMacs.contains(d.macAddress)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Returns all unknown/unnamed devices (devices in database without custom names,
  /// plus active ARP table hosts without custom names).
  List<UnknownDeviceEntry> get allUnknownDevices {
    final knownMacs = allKnownCustomDevices.map((d) => d.macAddress).toSet();
    final results = <UnknownDeviceEntry>[];
    final seenKeys = <String>{};

    // 1. Devices in SharedDeviceDatabase without custom names
    if (SharedDeviceDatabase.instance.isInitialized) {
      try {
        final allDbDevices = SharedDeviceDatabase.instance.getAllDevices(hideDefaultNamed: false);
        for (final dev in allDbDevices) {
          if (!dev.hasCustomName) {
            final key = dev.macAddress;
            if (seenKeys.add(key)) {
              final isShown = _showAutoDetected || _explicitlyShownMacs.contains(key);
              results.add(UnknownDeviceEntry(
                key: key,
                macAddress: dev.macAddress,
                displayName: dev.name.isNotEmpty ? dev.name : 'Device ${dev.macAddress}',
                vendor: dev.vendor,
                isInDatabase: true,
                isHidden: !isShown,
              ));
            }
          }
        }
      } catch (_) {}
    }

    // 2. Active ARP hosts without custom names
    for (final host in _hosts) {
      final normMac = SharedDevice.isValidMac(host.macAddress)
          ? SharedDevice.normalizeMac(host.macAddress)
          : host.macAddress.toUpperCase();
      if (knownMacs.contains(normMac)) continue;

      final key = normMac;
      if (seenKeys.add(key)) {
        final isShown = _showAutoDetected || _explicitlyShownMacs.contains(key);
        final displayName = (host.hostname != null && host.hostname!.trim().isNotEmpty)
            ? host.hostname!.trim()
            : (host.customName?.isNotEmpty == true ? host.customName! : 'Device $normMac');
        results.add(UnknownDeviceEntry(
          key: key,
          macAddress: normMac,
          ip: host.ipAddress,
          displayName: displayName,
          vendor: host.vendor,
          isInDatabase: false,
          isHidden: !isShown,
        ));
      }
    }

    return results;
  }

  /// Unknown devices that are unhidden and shown as filter pills.
  List<UnknownDeviceEntry> get visibleUnknownDevices =>
      allUnknownDevices.where((d) => !d.isHidden).toList();

  /// Returns active auto-detected hosts currently in the ARP table that do not have
  /// a custom labeled entry in visibleSharedDevices and are shown.
  List<ArpHostRecord> get autoDetectedUnlabeledHosts {
    final labeledMacs = visibleSharedDevices.map((d) => d.macAddress).toSet();
    final seen = <String>{};
    final result = <ArpHostRecord>[];
    for (final host in _hosts) {
      final mac = SharedDevice.isValidMac(host.macAddress)
          ? SharedDevice.normalizeMac(host.macAddress)
          : host.macAddress.toUpperCase();
      if (labeledMacs.contains(mac)) continue;

      final isShown = _showAutoDetected || _explicitlyShownMacs.contains(mac);
      if (!isShown) continue;

      if (seen.add(mac)) {
        result.add(host);
      }
    }
    return result;
  }

  Future<void> _init() async {
    await _loadPreferences();
    if (_isDisposed) return;
    _initSharedDbListener();
    await refreshAdapters();
    if (_isDisposed) return;
    if (initialAdapterIp != null || initialAdapterName != null) {
      selectMatchingAdapter(
        adapterIp: initialAdapterIp,
        adapterName: initialAdapterName,
      );
    }
    final subnet = initialSubnet;
    if (subnet != null && subnet.trim().isNotEmpty) {
      updateTargetSubnet(subnet.trim());
    }
    _refreshQuery();
    if (initialAutoStart) {
      unawaited(startSubnetScan(subnetOverride: initialSubnet));
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await ArpScoutPreferencesService.loadPreferences();
      _showAutoDetected = prefs.showAutoDetected;
      _hiddenDeviceMacs = prefs.hiddenDeviceMacs;
      _explicitlyShownMacs = prefs.explicitlyShownMacs;
      if (prefs.selectedDeviceMacs.isNotEmpty) {
        _filter = _filter.copyWith(selectedDeviceMacs: prefs.selectedDeviceMacs);
      }
    } catch (_) {}
  }

  void _savePreferences() {
    ArpScoutPreferencesService.savePreferences(
      ArpScoutPreferences(
        showAutoDetected: _showAutoDetected,
        hiddenDeviceMacs: _hiddenDeviceMacs,
        explicitlyShownMacs: _explicitlyShownMacs,
        selectedDeviceMacs: _filter.selectedDeviceMacs,
      ),
    );
  }

  void setShowAutoDetected(bool value) {
    if (_showAutoDetected == value) return;
    _showAutoDetected = value;
    _savePreferences();
    notifyListeners();
  }

  void toggleDeviceVisibility(String key) {
    final normalized = SharedDevice.isValidMac(key) ? SharedDevice.normalizeMac(key) : key;
    final isKnown = allKnownCustomDevices.any((d) => d.macAddress == normalized);

    if (!isKnown) {
      final isShown = _showAutoDetected || _explicitlyShownMacs.contains(normalized);
      if (isShown) {
        _explicitlyShownMacs = Set.from(_explicitlyShownMacs)..remove(normalized);
        if (_filter.selectedDeviceMacs.contains(normalized)) {
          toggleDevicePill(normalized);
        }
      } else {
        _explicitlyShownMacs = Set.from(_explicitlyShownMacs)..add(normalized);
      }
    } else {
      if (_hiddenDeviceMacs.contains(normalized)) {
        _hiddenDeviceMacs = Set.from(_hiddenDeviceMacs)..remove(normalized);
      } else {
        _hiddenDeviceMacs = Set.from(_hiddenDeviceMacs)..add(normalized);
        if (_filter.selectedDeviceMacs.contains(normalized)) {
          toggleDevicePill(normalized);
        }
      }
    }
    _savePreferences();
    notifyListeners();
  }

  void setDeviceHidden(String key, bool isHidden) {
    final normalized = SharedDevice.isValidMac(key) ? SharedDevice.normalizeMac(key) : key;
    final isKnown = allKnownCustomDevices.any((d) => d.macAddress == normalized);

    if (!isKnown) {
      if (isHidden) {
        _explicitlyShownMacs = Set.from(_explicitlyShownMacs)..remove(normalized);
        if (_filter.selectedDeviceMacs.contains(normalized)) {
          toggleDevicePill(normalized);
        }
      } else {
        _explicitlyShownMacs = Set.from(_explicitlyShownMacs)..add(normalized);
      }
    } else {
      if (isHidden) {
        _hiddenDeviceMacs = Set.from(_hiddenDeviceMacs)..add(normalized);
        if (_filter.selectedDeviceMacs.contains(normalized)) {
          toggleDevicePill(normalized);
        }
      } else {
        _hiddenDeviceMacs = Set.from(_hiddenDeviceMacs)..remove(normalized);
      }
    }
    _savePreferences();
    notifyListeners();
  }

  void unhideAllDevices() {
    _hiddenDeviceMacs = {};
    _explicitlyShownMacs = {};
    _showAutoDetected = true;
    _savePreferences();
    _refreshQuery();
  }

  void toggleDevicePill(String mac) {
    final normalized = SharedDevice.normalizeMac(mac);
    final current = Set<String>.from(_filter.selectedDeviceMacs);
    if (current.contains(normalized)) {
      current.remove(normalized);
    } else {
      current.add(normalized);
    }
    _filter = _filter.copyWith(selectedDeviceMacs: current);
    _savePreferences();
    _refreshQuery();
  }

  void clearDeviceFilters() {
    if (_filter.selectedDeviceMacs.isEmpty) return;
    _filter = _filter.copyWith(selectedDeviceMacs: const {});
    _savePreferences();
    _refreshQuery();
  }

  void updateDeviceMetadata({
    required String mac,
    required String name,
    String? category,
    String? vendor,
    String? notes,
  }) {
    _repository.updateDeviceDetails(
      macAddress: mac,
      name: name,
      deviceType: category,
      vendor: vendor,
      notes: notes,
    );
    final normalized = SharedDevice.normalizeMac(mac);
    _hiddenDeviceMacs = Set.from(_hiddenDeviceMacs)..remove(normalized);
    _explicitlyShownMacs = Set.from(_explicitlyShownMacs)..remove(normalized);
    _savePreferences();
    _refreshQuery();
  }

  void _initSharedDbListener() {
    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        _repository.syncAllSharedDeviceNamesToLocalDb();
        _sharedDbSubscription = SharedDeviceDatabase.instance.onDatabaseChanged.listen((_) {
          _repository.syncAllSharedDeviceNamesToLocalDb();
          _refreshQuery();
        });
      }
    } catch (e) {
      debugPrint('Shared device listener init error: $e');
    }
  }

  /// Updates a friendly device name and syncs across Network Suite applications.
  void updateDeviceName(String macAddress, String newName) {
    _repository.updateDeviceName(macAddress, newName);
    _refreshQuery();
  }

  Future<void> refreshAdapters() async {
    final list = await _repository.getAvailableAdapters();
    _adapters = list.isNotEmpty ? list : [NetworkAdapterInfo.all];
    if (!_adapters.contains(_selectedAdapter)) {
      _selectedAdapter = _adapters.first;
    }
    final defaultSubnet = _selectedAdapter.subnetCidr;
    _scanProgress = _scanProgress.copyWith(
      targetSubnet: defaultSubnet,
      generatedCommand: SubnetScannerService.buildCliPreviewCommand(
        defaultSubnet,
        arpOnly: _selectedAdapter.isAllInterfaces,
      ),
    );
    notifyListeners();
  }

  void selectAdapter(NetworkAdapterInfo adapter) {
    _selectedAdapter = adapter;
    final subnet = adapter.subnetCidr;
    _scanProgress = _scanProgress.copyWith(
      targetSubnet: subnet,
      generatedCommand: SubnetScannerService.buildCliPreviewCommand(
        subnet,
        arpOnly: adapter.isAllInterfaces,
      ),
    );
    notifyListeners();
  }

  /// Selects the local network adapter matching [adapterIp] (primary) or [adapterName] (secondary).
  void selectMatchingAdapter({String? adapterIp, String? adapterName}) {
    if (_adapters.isEmpty) return;

    // 1. Primary match: by IP address (exact physical interface match)
    if (adapterIp != null && adapterIp.trim().isNotEmpty) {
      final targetIp = adapterIp.trim();
      final match = _adapters.firstWhere(
        (a) => a.ipAddress == targetIp,
        orElse: () => NetworkAdapterInfo.all,
      );
      if (match != NetworkAdapterInfo.all) {
        selectAdapter(match);
        return;
      }
    }

    // 2. Secondary match: by Interface Name (e.g. "eth0")
    if (adapterName != null && adapterName.trim().isNotEmpty) {
      final targetName = adapterName.trim().toLowerCase();
      final match = _adapters.firstWhere(
        (a) => a.name.toLowerCase() == targetName,
        orElse: () => NetworkAdapterInfo.all,
      );
      if (match != NetworkAdapterInfo.all) {
        selectAdapter(match);
        return;
      }
    }
  }

  /// Handles incoming subnet scan command from CLI or IPC warm handoff from Net Route Scout.
  Future<void> handleIncomingCommand({
    String? subnet,
    String? adapterIp,
    String? adapterName,
    bool autoStart = false,
  }) async {
    // If adapters are not yet refreshed or only have fallback, refresh them
    if (_adapters.isEmpty ||
        (_adapters.length == 1 && _adapters.first == NetworkAdapterInfo.all)) {
      await refreshAdapters();
    }

    if (adapterIp != null || adapterName != null) {
      selectMatchingAdapter(adapterIp: adapterIp, adapterName: adapterName);
    }

    if (subnet != null && subnet.trim().isNotEmpty) {
      updateTargetSubnet(subnet.trim());
    }

    if (autoStart) {
      await startSubnetScan(subnetOverride: subnet);
    }
  }

  void updateTargetSubnet(String subnet) {
    final trimmed = subnet.trim();
    if (trimmed.isEmpty) return;
    _scanProgress = _scanProgress.copyWith(
      targetSubnet: trimmed,
      generatedCommand: SubnetScannerService.buildCliPreviewCommand(
        trimmed,
        arpOnly: _selectedAdapter.isAllInterfaces,
      ),
    );
    notifyListeners();
  }

  /// Launches an active L2 ARP + L3 ICMP Subnet Sweep.
  Future<void> startSubnetScan({
    String? subnetOverride,
    bool arpCacheOnly = false,
  }) async {
    if (_scanProgress.isScanning) return;

    final targetSubnet =
        (subnetOverride != null && subnetOverride.trim().isNotEmpty)
        ? subnetOverride.trim()
        : _scanProgress.targetSubnet;

    final targetIps = arpCacheOnly
        ? const <String>[]
        : SubnetScannerService.expandTargetSubnet(targetSubnet);

    if (!arpCacheOnly && targetIps.isEmpty) {
      _scanProgress = _scanProgress.copyWith(
        lastError:
            'Invalid subnet CIDR or IP range "$targetSubnet". Use format 192.168.1.0/24 or 192.168.1.1-254.',
      );
      notifyListeners();
      return;
    }

    _scanProgress = _scanProgress.copyWith(
      isScanning: true,
      targetSubnet: targetSubnet,
      probedHosts: 0,
      totalHosts: targetIps.length,
      currentPhase: arpCacheOnly
          ? 'Reading OS L2 ARP Table...'
          : 'Starting L2/L3 Subnet Sweep...',
      clearError: true,
      generatedCommand: SubnetScannerService.buildCliPreviewCommand(
        targetSubnet,
        arpOnly: arpCacheOnly,
      ),
      sweepIteration: _scanProgress.sweepIteration + 1,
    );
    notifyListeners();

    try {
      final results = await _repository.performSubnetSweep(
        targetSubnet: targetSubnet,
        interfaceName: _selectedAdapter.name,
        localInterfaceIp: _selectedAdapter.isAllInterfaces
            ? null
            : _selectedAdapter.ipAddress,
        arpCacheOnly: arpCacheOnly,
        onProgress: (probed, total, phase, partialBatch) {
          if (partialBatch.isNotEmpty) {
            _repository.upsertBatch(partialBatch);
          }
          _scanProgress = _scanProgress.copyWith(
            probedHosts: probed,
            totalHosts: total,
            currentPhase: phase,
          );
          if (partialBatch.isNotEmpty) {
            _refreshQuery(notify: false);
          }
          notifyListeners();
        },
      );

      if (_repository.scannerService.isCancelled) {
        _repository.cleanupCancelledSweep();
        _refreshQuery();
        return;
      }

      if (results.isNotEmpty) {
        _repository.upsertBatch(results);
      }

      _repository.reconcileSweepCompletion(
        subnet: targetSubnet,
        activeIps: results.map((r) => r.ipAddress).toSet(),
        markMissingAsStale: !arpCacheOnly && targetIps.length > 1,
      );

      _scanProgress = _scanProgress.copyWith(
        isScanning: false,
        probedHosts: _scanProgress.totalHosts,
        discoveredInLastSweep: results.length,
        currentPhase:
            'Sweep Complete (${results.length} active L2/L3 records updated)',
        lastScanCompletedAt: DateTime.now(),
      );
      _refreshQuery();
    } catch (e) {
      _repository.cleanupCancelledSweep();
      _scanProgress = _scanProgress.copyWith(
        isScanning: false,
        currentPhase: 'Scan Failed',
        lastError: 'Subnet scan error: $e',
      );
      notifyListeners();
    }
  }

  /// Dismisses any visible error alert banner.
  void dismissError() {
    if (_scanProgress.lastError == null) return;
    _scanProgress = _scanProgress.copyWith(clearError: true);
    notifyListeners();
  }

  /// Stops an active scan and cancels any continuous watch timer.
  Future<void> stopScan() async {
    _watchTimer?.cancel();
    _watchTimer = null;
    await _repository.cancelActiveScan();
    _repository.cleanupCancelledSweep();
    _scanProgress = _scanProgress.copyWith(
      isScanning: false,
      isContinuousWatch: false,
      currentPhase: 'Scan Stopped',
    );
    _refreshQuery();
  }

  /// Toggles Continuous Watch Mode (periodic ARP/ICMP sweeps to catch intermittent IP conflicts).
  void toggleContinuousWatch({String? subnetOverride}) {
    if (_scanProgress.isContinuousWatch) {
      _watchTimer?.cancel();
      _watchTimer = null;
      _scanProgress = _scanProgress.copyWith(
        isContinuousWatch: false,
        currentPhase: 'Continuous Watch Paused',
      );
      notifyListeners();
      return;
    }

    if (subnetOverride != null && subnetOverride.trim().isNotEmpty) {
      updateTargetSubnet(subnetOverride);
    }

    _scanProgress = _scanProgress.copyWith(
      isContinuousWatch: true,
      clearError: true,
    );
    notifyListeners();

    // Trigger immediate sweep, then repeat every watchIntervalSeconds
    startSubnetScan(subnetOverride: subnetOverride);
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(
      Duration(seconds: _scanProgress.watchIntervalSeconds),
      (_) {
        if (!_scanProgress.isScanning && _scanProgress.isContinuousWatch) {
          startSubnetScan();
        }
      },
    );
  }

  /// Re-probes a single host via ICMP + ARP cache refresh.
  Future<void> reprobeSingleHost(ArpHostRecord record) async {
    await startSubnetScan(subnetOverride: '${record.ipAddress}/32');
  }

  /// Loads built-in realistic enterprise subnet topology (with IP conflicts & multi-homed MACs).
  void loadDemoTopology() {
    _loadedFileName = null;
    _repository.loadDemoTopology(subnetCidr: '192.168.10.0/24');
    _scanProgress = _scanProgress.copyWith(
      targetSubnet: '192.168.10.0/24',
      lastScanCompletedAt: DateTime.now(),
      currentPhase: 'Loaded Demo Enterprise Subnet (192.168.10.0/24)',
      clearError: true,
    );
    _refreshQuery();
  }

  /// Simulates a Gratuitous ARP conflict on an existing online host to demonstrate real-time conflict detection.
  void simulateRogueMacConflict({ArpHostRecord? target}) {
    final candidate =
        target ??
        _hosts.firstWhere(
          (h) => h.status != HostStatus.conflict,
          orElse: () => _hosts.isNotEmpty
              ? _hosts.first
              : ArpHostRecord(
                  ipAddress: '192.168.10.25',
                  ipNumeric: ArpHostRecord.ipv4ToInt('192.168.10.25'),
                  macAddress: '00:15:5D:0A:25:01',
                  vendor: 'Microsoft Hyper-V',
                  subnet: '192.168.10.0/24',
                  interfaceName: 'Ethernet0',
                  status: HostStatus.online,
                  discoveryMethod: 'ARP + ICMP',
                  firstSeenMs: DateTime.now().millisecondsSinceEpoch,
                  lastSeenMs: DateTime.now().millisecondsSinceEpoch,
                ),
        );

    const rogueMac = 'B8:27:EB:99:88:77';
    final rogueVendor = OuiLookupService.lookupVendor(rogueMac);
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final conflictingObservation = candidate.copyWith(
      macAddress: rogueMac,
      vendor: rogueVendor,
      discoveryMethod: 'Gratuitous ARP (Conflict)',
      lastSeenMs: nowMs,
      notes: '',
    );

    _repository.upsertBatch([conflictingObservation]);
    _refreshQuery();
  }

  void setSearchQuery(String query) {
    _filter = _filter.copyWith(searchQuery: query);
    _refreshQuery();
  }

  void setIpFilter(String ip) {
    _filter = _filter.copyWith(ipFilter: ip);
    _refreshQuery();
  }

  void setMacFilter(String mac) {
    _filter = _filter.copyWith(macFilter: mac);
    _refreshQuery();
  }

  void setVendorFilter(String vendor) {
    _filter = _filter.copyWith(vendorFilter: vendor);
    _refreshQuery();
  }

  void toggleStatus(HostStatus status) {
    final next = Set<HostStatus>.from(_filter.selectedStatuses);
    if (next.contains(status)) {
      next.remove(status);
    } else {
      next.add(status);
    }
    _filter = _filter.copyWith(
      selectedStatuses: next,
      conflictsOnly: false,
    );
    _refreshQuery();
  }

  void toggleConflictsOnly() {
    final nextConflictsOnly = !_filter.conflictsOnly;
    _filter = _filter.copyWith(
      conflictsOnly: nextConflictsOnly,
      selectedStatuses: nextConflictsOnly ? {HostStatus.conflict} : {},
    );
    _refreshQuery();
  }

  void resetFilters() {
    _filter = ArpFilterCriteria(
      sortColumn: _filter.sortColumn,
      sortAscending: _filter.sortAscending,
    );
    _refreshQuery();
  }

  void setSort(String columnKey) {
    if (_filter.sortColumn == columnKey) {
      _filter = _filter.copyWith(sortAscending: !_filter.sortAscending);
    } else {
      _filter = _filter.copyWith(sortColumn: columnKey, sortAscending: true);
    }
    _refreshQuery();
  }

  void selectRecord(ArpHostRecord? record) {
    _selectedRecord = record;
    notifyListeners();
  }

  void loadMoreHosts() {
    if (_isLoadingMore || !hasMoreHosts) return;
    _isLoadingMore = true;
    notifyListeners();

    final nextBatch = _repository.queryHosts(
      offset: _hosts.length,
      limit: pageSize,
      filter: _filter,
    );
    _hosts = [..._hosts, ...nextBatch];
    _isLoadingMore = false;
    notifyListeners();
  }

  void clearHosts() {
    _repository.clearAll();
    _selectedRecord = null;
    _loadedFileName = null;
    _refreshQuery();
  }

  Future<CsvImportResult?> importCsvFile({bool replaceExisting = false}) async {
    _isImporting = true;
    notifyListeners();
    try {
      final res = await _repository.importCsvFile(
        replaceExisting: replaceExisting,
      );
      if (res != null) {
        _loadedFileName = res.fileName;
        _scanProgress = _scanProgress.copyWith(clearError: true);
        _refreshQuery(notify: false);
      }
      return res;
    } catch (e) {
      _scanProgress = _scanProgress.copyWith(
        lastError: 'CSV Import failed: $e',
      );
      return null;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  void closeLoadedFile() {
    _loadedFileName = null;
    clearHosts();
  }

  Future<String?> exportCsv() => _repository.exportCsv(_filter);

  Future<String?> exportJson() => _repository.exportJson(_filter);

  void _refreshQuery({bool notify = true}) {
    _totalHostCount = _repository.countHosts(_filter);
    _unfilteredTotalCount = _repository.totalUnfilteredCount();
    _statusCounts = _repository.getStatusCounts(_filter);
    _deviceCounts = _repository.getDeviceHostCounts(_filter);
    final currentLimit = _hosts.length > pageSize ? _hosts.length : pageSize;
    _hosts = _repository.queryHosts(
      offset: 0,
      limit: currentLimit,
      filter: _filter,
    );

    if (_selectedRecord != null) {
      final updated = _hosts.where(
        (h) => h.ipAddress == _selectedRecord!.ipAddress,
      );
      _selectedRecord = updated.isNotEmpty ? updated.first : _selectedRecord;
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> stopAllServices() async {
    await stopScan();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _watchTimer?.cancel();
    _sharedDbSubscription?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
