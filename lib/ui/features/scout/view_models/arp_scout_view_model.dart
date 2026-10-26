import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../data/repositories/arp_repository.dart';
import '../../../../data/services/import/csv_import_service.dart';
import '../../../../data/services/oui/oui_lookup_service.dart';
import '../../../../data/services/scanner/subnet_scanner_service.dart';
import '../../../../domain/models/arp_filter.dart';
import '../../../../domain/models/arp_host_record.dart';
import '../../../../domain/models/host_status.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../../../../domain/models/scan_progress.dart';

class ArpScoutViewModel extends ChangeNotifier {
  ArpScoutViewModel({ArpRepository? repository})
    : _repository = repository ?? ArpRepository() {
    _init();
  }

  final ArpRepository _repository;
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

  List<NetworkAdapterInfo> get adapters => _adapters;
  NetworkAdapterInfo get selectedAdapter => _selectedAdapter;
  ArpFilterCriteria get filter => _filter;
  ScanProgress get scanProgress => _scanProgress;
  List<ArpHostRecord> get hosts => _hosts;
  Map<HostStatus, int> get statusCounts => _statusCounts;
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

  Future<void> _init() async {
    await refreshAdapters();
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
    _statusCounts = _repository.getStatusCounts();
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
  void dispose() {
    _watchTimer?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
