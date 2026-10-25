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

  void upsertBatch(List<ArpHostRecord> records) {
    _dbService.upsertBatch(records);
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
    _dbService.upsertBatch(demoRecords);
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
    _dbService.upsertBatch(result.records);
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
