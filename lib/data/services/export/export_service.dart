import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../../../domain/models/arp_host_record.dart';

class ExportService {
  static bool _isFormulaTrigger(String ch) {
    return ch == '=' ||
        ch == '+' ||
        ch == '-' ||
        ch == '@' ||
        ch == '\t' ||
        ch == '\r' ||
        ch == '\n' ||
        ch == '|';
  }

  static String sanitizeForCsv(String? value) {
    if (value == null || value.isEmpty) return '';
    final firstChar = value[0];
    final trimmed = value.trimLeft();
    final firstNonSpace = trimmed.isNotEmpty ? trimmed[0] : '';
    if (_isFormulaTrigger(firstChar) ||
        (firstNonSpace.isNotEmpty && _isFormulaTrigger(firstNonSpace))) {
      return "'$value";
    }
    return value;
  }

  static Future<String?> exportToCsv(List<ArpHostRecord> records) async {
    final rows = <List<dynamic>>[
      [
        'IP Address',
        'MAC Address',
        'Vendor (OUI)',
        'Hostname',
        'Status',
        'Discovery Method',
        'ARP Type',
        'RTT (ms)',
        'TTL',
        'Subnet',
        'Interface',
        'Conflicting MACs',
        'Associated IPs',
        'First Seen',
        'Last Seen',
        'Notes',
      ],
      ...records.map(
        (r) => [
          sanitizeForCsv(r.ipAddress),
          sanitizeForCsv(r.macAddress),
          sanitizeForCsv(r.vendor),
          sanitizeForCsv(r.hostname),
          sanitizeForCsv(r.status.label),
          sanitizeForCsv(r.discoveryMethod),
          sanitizeForCsv(r.arpType),
          r.rttMs?.toStringAsFixed(2) ?? '',
          r.ttl?.toString() ?? '',
          sanitizeForCsv(r.subnet),
          sanitizeForCsv(r.interfaceName),
          sanitizeForCsv(r.conflictingMacs.join(' | ')),
          sanitizeForCsv(r.associatedIps.join(' | ')),
          r.firstSeen.toIso8601String(),
          r.lastSeen.toIso8601String(),
          sanitizeForCsv(r.notes),
        ],
      ),
    ];

    final csvContent = Csv().encode(rows);
    final bytes = Uint8List.fromList(utf8.encode(csvContent));
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export ARP & Subnet Table as CSV',
      fileName:
          'arp_scout_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.csv',
      bytes: bytes,
    );

    if (uri == null) return null;
    try {
      return uri.toFilePath();
    } catch (_) {
      return uri.path;
    }
  }

  static Future<String?> exportToJson(List<ArpHostRecord> records) async {
    final jsonString = const JsonEncoder.withIndent('  ').convert(
      records.map((r) => r.toJson()).toList(),
    );
    final bytes = Uint8List.fromList(utf8.encode(jsonString));
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Export ARP & Subnet Table as JSON',
      fileName:
          'arp_scout_${DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first}.json',
      bytes: bytes,
    );

    if (uri == null) return null;
    try {
      return uri.toFilePath();
    } catch (_) {
      return uri.path;
    }
  }
}
