import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../../../domain/models/arp_host_record.dart';
import '../../../domain/models/host_status.dart';
import '../oui/oui_lookup_service.dart';

class CsvImportResult {
  const CsvImportResult({
    required this.fileName,
    required this.records,
    required this.skippedCount,
  });

  final String fileName;
  final List<ArpHostRecord> records;
  final int skippedCount;
}

class CsvImportService {
  static Future<CsvImportResult?> pickAndParseCsv() async {
    final pickedFiles = await FilePicker.pickFiles(
      dialogTitle: 'Open ARP / Subnet CSV File',
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
    );

    if (pickedFiles.isEmpty) return null;
    final path = pickedFiles.single.path;
    if (path == null) return null;

    return parseCsvFile(File(path));
  }

  static Future<CsvImportResult> parseCsvFile(File file) async {
    final content = await file.readAsString();
    final rows = Csv().decode(content);
    if (rows.isEmpty) {
      return CsvImportResult(
        fileName: file.uri.pathSegments.last,
        records: const [],
        skippedCount: 0,
      );
    }

    final header = rows.first
        .map((e) => e.toString().trim().toLowerCase())
        .toList();
    final hasHeader = header.any(
      (h) => h.contains('ip') || h.contains('mac') || h.contains('address'),
    );

    final ipIdx = _findCol(header, ['ip address', 'ip_address', 'ip', 'host'], 0);
    final macIdx = _findCol(
      header,
      ['mac address', 'mac_address', 'mac', 'physical'],
      1,
    );
    final vendorIdx = _findCol(header, ['vendor', 'oui', 'manufacturer'], 2);
    final hostIdx = _findCol(
      header,
      ['hostname', 'host name', 'name', 'dns'],
      3,
    );
    final statusIdx = _findCol(header, ['status', 'state'], 4);
    final rttIdx = _findCol(header, ['rtt', 'latency', 'ping'], 7);
    final ttlIdx = _findCol(header, ['ttl'], 8);
    final notesIdx = _findCol(header, ['notes', 'description', 'comment'], 15);

    final startRow = hasHeader ? 1 : 0;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final records = <ArpHostRecord>[];
    var skipped = 0;

    for (var i = startRow; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      final ip = _cell(row, ipIdx);
      if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(ip)) {
        skipped++;
        continue;
      }

      final rawMac = _cell(row, macIdx);
      final normalizedMac = rawMac.isNotEmpty
          ? ArpHostRecord.normalizeMac(rawMac)
          : 'UNRESOLVED';
      final rawVendor = _cell(row, vendorIdx);
      final vendor = rawVendor.isNotEmpty
          ? rawVendor
          : OuiLookupService.lookupVendor(normalizedMac);
      final hostname = _cell(row, hostIdx);
      final statusStr = _cell(row, statusIdx).toUpperCase();
      final rtt = double.tryParse(_cell(row, rttIdx));
      final ttl = int.tryParse(_cell(row, ttlIdx));
      final notes = _cell(row, notesIdx);

      var status = HostStatus.online;
      if (statusStr.contains('CONFLICT')) {
        status = HostStatus.conflict;
      } else if (statusStr.contains('ARP')) {
        status = HostStatus.arpOnly;
      } else if (statusStr.contains('ICMP')) {
        status = HostStatus.icmpOnly;
      } else if (statusStr.contains('STALE') || statusStr.contains('OFFLINE')) {
        status = HostStatus.stale;
      }

      final octets = ip.split('.');
      final subnet = '${octets[0]}.${octets[1]}.${octets[2]}.0/24';

      records.add(
        ArpHostRecord(
          ipAddress: ip,
          ipNumeric: ArpHostRecord.ipv4ToInt(ip),
          macAddress: normalizedMac,
          vendor: vendor,
          hostname: hostname.isEmpty ? null : hostname,
          subnet: subnet,
          interfaceName: 'CSV Import',
          status: status,
          discoveryMethod: 'CSV Import',
          rttMs: rtt,
          ttl: ttl,
          firstSeenMs: nowMs,
          lastSeenMs: nowMs,
          conflictingMacs:
              normalizedMac != 'UNRESOLVED' ? [normalizedMac] : const [],
          notes: notes,
        ),
      );
    }

    return CsvImportResult(
      fileName: file.uri.pathSegments.last,
      records: records,
      skippedCount: skipped,
    );
  }

  static int _findCol(
    List<String> headers,
    List<String> candidates,
    int fallback,
  ) {
    for (final c in candidates) {
      final idx = headers.indexWhere((h) => h.contains(c));
      if (idx != -1) return idx;
    }
    return fallback;
  }

  static String _cell(List<dynamic> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index]?.toString().trim() ?? '';
  }
}
