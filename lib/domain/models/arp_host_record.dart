import 'dart:convert';
import 'dart:typed_data';
import 'host_status.dart';

class ArpHostRecord {
  const ArpHostRecord({
    this.id,
    required this.ipAddress,
    required this.ipNumeric,
    required this.macAddress,
    required this.vendor,
    this.hostname,
    required this.subnet,
    required this.interfaceName,
    required this.status,
    required this.discoveryMethod,
    this.arpType = 'dynamic',
    this.rttMs,
    this.ttl,
    required this.firstSeenMs,
    required this.lastSeenMs,
    this.responseCount = 1,
    this.conflictingMacs = const [],
    this.associatedIps = const [],
    this.notes = '',
    this.rawArpLine = '',
  });

  final int? id;
  final String ipAddress;
  final int ipNumeric;
  final String macAddress;
  final String vendor;
  final String? hostname;
  final String subnet;
  final String interfaceName;
  final HostStatus status;
  final String discoveryMethod;
  final String arpType;
  final double? rttMs;
  final int? ttl;
  final int firstSeenMs;
  final int lastSeenMs;
  final int responseCount;
  final List<String> conflictingMacs;
  final List<String> associatedIps;
  final String notes;
  final String rawArpLine;

  DateTime get firstSeen => DateTime.fromMillisecondsSinceEpoch(firstSeenMs);
  DateTime get lastSeen => DateTime.fromMillisecondsSinceEpoch(lastSeenMs);

  bool get hasConflict =>
      status == HostStatus.conflict || conflictingMacs.length > 1;

  /// Infers likely operating system / device family from ICMP TTL value.
  String get osHintFromTtl {
    final t = ttl;
    if (t == null) return '-';
    if (t <= 64) return 'Linux / macOS / IoT (TTL $t)';
    if (t <= 128) return 'Windows (TTL $t)';
    return 'Network Gear / Cisco / Solaris (TTL $t)';
  }

  /// Normalizes any MAC string into uppercase colon-separated format (AA:BB:CC:DD:EE:FF).
  static String normalizeMac(String raw) {
    final cleaned = raw
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^0-9A-F]'), '');
    if (cleaned.length != 12) {
      return raw.trim().toUpperCase();
    }
    final parts = <String>[];
    for (var i = 0; i < 12; i += 2) {
      parts.add(cleaned.substring(i, i + 2));
    }
    return parts.join(':');
  }

  /// Validates whether [ip] is a strictly well-formed dotted-quad IPv4 address (octets 0..255).
  static bool isValidIpv4(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) return false;
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return false;
      if (part.length > 1 && part.startsWith('0')) return false;
    }
    return true;
  }

  /// Converts an IPv4 string (e.g., 192.168.1.10) to a 32-bit integer for numeric sorting.
  /// Returns 0 if [ip] is not a valid IPv4 address.
  static int ipv4ToInt(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return 0;
    var result = 0;
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) return 0;
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return 0;
      result = (result << 8) | (octet & 0xFF);
    }
    return result;
  }

  /// Converts a 32-bit integer back into an IPv4 string.
  static String intToIpv4(int value) {
    final a = (value >> 24) & 0xFF;
    final b = (value >> 16) & 0xFF;
    final c = (value >> 8) & 0xFF;
    final d = value & 0xFF;
    return '$a.$b.$c.$d';
  }

  /// Synthesizes a 42-byte Ethernet II + IPv4 ARP Reply frame for the Hex/ASCII inspector.
  Uint8List toSyntheticArpFrameBytes({String? targetIp, String? targetMac}) {
    final bytes = Uint8List(42);
    final srcMacBytes = _macToBytes(macAddress);
    final dstMacBytes = _macToBytes(targetMac ?? 'FF:FF:FF:FF:FF:FF');
    final srcIpBytes = _ipToBytes(ipAddress);
    final dstIpBytes = _ipToBytes(targetIp ?? _gatewayIpFor(ipAddress));

    // Ethernet II Header (14 bytes)
    bytes.setRange(0, 6, dstMacBytes);
    bytes.setRange(6, 12, srcMacBytes);
    bytes[12] = 0x08; // EtherType: ARP (0x0806)
    bytes[13] = 0x06;

    // ARP Payload (28 bytes)
    bytes[14] = 0x00;
    bytes[15] = 0x01; // Hardware Type: Ethernet (1)
    bytes[16] = 0x08;
    bytes[17] = 0x00; // Protocol Type: IPv4 (0x0800)
    bytes[18] = 0x06; // Hardware Size: 6
    bytes[19] = 0x04; // Protocol Size: 4
    bytes[20] = 0x00;
    bytes[21] = 0x02; // Opcode: ARP Reply (2)
    bytes.setRange(22, 28, srcMacBytes); // Sender MAC
    bytes.setRange(28, 32, srcIpBytes); // Sender IP
    bytes.setRange(32, 38, dstMacBytes); // Target MAC
    bytes.setRange(38, 42, dstIpBytes); // Target IP

    return bytes;
  }

  static List<int> _macToBytes(String mac) {
    final clean = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (clean.length != 12) return List<int>.filled(6, 0);
    return List<int>.generate(
      6,
      (i) => int.tryParse(clean.substring(i * 2, i * 2 + 2), radix: 16) ?? 0,
    );
  }

  static List<int> _ipToBytes(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return List<int>.filled(4, 0);
    return parts.map((e) => (int.tryParse(e) ?? 0) & 0xFF).toList();
  }

  static String _gatewayIpFor(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return '192.168.1.1';
    return '${parts[0]}.${parts[1]}.${parts[2]}.1';
  }

  ArpHostRecord copyWith({
    int? id,
    String? ipAddress,
    int? ipNumeric,
    String? macAddress,
    String? vendor,
    String? hostname,
    String? subnet,
    String? interfaceName,
    HostStatus? status,
    String? discoveryMethod,
    String? arpType,
    double? rttMs,
    int? ttl,
    int? firstSeenMs,
    int? lastSeenMs,
    int? responseCount,
    List<String>? conflictingMacs,
    List<String>? associatedIps,
    String? notes,
    String? rawArpLine,
  }) {
    return ArpHostRecord(
      id: id ?? this.id,
      ipAddress: ipAddress ?? this.ipAddress,
      ipNumeric: ipNumeric ?? this.ipNumeric,
      macAddress: macAddress ?? this.macAddress,
      vendor: vendor ?? this.vendor,
      hostname: hostname ?? this.hostname,
      subnet: subnet ?? this.subnet,
      interfaceName: interfaceName ?? this.interfaceName,
      status: status ?? this.status,
      discoveryMethod: discoveryMethod ?? this.discoveryMethod,
      arpType: arpType ?? this.arpType,
      rttMs: rttMs ?? this.rttMs,
      ttl: ttl ?? this.ttl,
      firstSeenMs: firstSeenMs ?? this.firstSeenMs,
      lastSeenMs: lastSeenMs ?? this.lastSeenMs,
      responseCount: responseCount ?? this.responseCount,
      conflictingMacs: conflictingMacs ?? this.conflictingMacs,
      associatedIps: associatedIps ?? this.associatedIps,
      notes: notes ?? this.notes,
      rawArpLine: rawArpLine ?? this.rawArpLine,
    );
  }

  factory ArpHostRecord.fromRow(Map<String, Object?> row) {
    final conflictsJson = row['conflicting_macs'] as String? ?? '[]';
    final ipsJson = row['associated_ips'] as String? ?? '[]';

    List<String> parseList(String raw) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
      return const [];
    }

    return ArpHostRecord(
      id: row['id'] as int?,
      ipAddress: row['ip_address'] as String? ?? '',
      ipNumeric: row['ip_numeric'] as int? ?? 0,
      macAddress: row['mac_address'] as String? ?? 'UNRESOLVED',
      vendor: row['vendor'] as String? ?? 'Unknown Vendor',
      hostname: row['hostname'] as String?,
      subnet: row['subnet'] as String? ?? '',
      interfaceName: row['interface_name'] as String? ?? '',
      status: HostStatus.fromCode(row['status'] as int? ?? 1),
      discoveryMethod: row['discovery_method'] as String? ?? 'ARP + ICMP',
      arpType: row['arp_type'] as String? ?? 'dynamic',
      rttMs: (row['rtt_ms'] as num?)?.toDouble(),
      ttl: row['ttl'] as int?,
      firstSeenMs: row['first_seen_ms'] as int? ?? 0,
      lastSeenMs: row['last_seen_ms'] as int? ?? 0,
      responseCount: row['response_count'] as int? ?? 1,
      conflictingMacs: parseList(conflictsJson),
      associatedIps: parseList(ipsJson),
      notes: row['notes'] as String? ?? '',
      rawArpLine: row['raw_arp_line'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'ipAddress': ipAddress,
      'macAddress': macAddress,
      'vendor': vendor,
      'hostname': hostname,
      'subnet': subnet,
      'interfaceName': interfaceName,
      'status': status.label,
      'discoveryMethod': discoveryMethod,
      'arpType': arpType,
      'rttMs': rttMs,
      'ttl': ttl,
      'firstSeen': firstSeen.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
      'responseCount': responseCount,
      'conflictingMacs': conflictingMacs,
      'associatedIps': associatedIps,
      'notes': notes,
      'rawArpLine': rawArpLine,
    };
  }
}
