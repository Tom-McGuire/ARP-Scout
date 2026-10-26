import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import '../../../domain/models/arp_filter.dart';
import '../../../domain/models/arp_host_record.dart';
import '../../../domain/models/host_status.dart';
import '../oui/oui_lookup_service.dart';

class ArpDatabaseService {
  ArpDatabaseService({
    Database? db,
    this.maxRows = 100000,
  }) : _db = db ?? sqlite3.openInMemory() {
    _initSchema();
  }

  final Database _db;
  final int maxRows;
  Database get db => _db;

  void _initSchema() {
    try {
      _db.execute('PRAGMA synchronous = NORMAL;');
    } catch (_) {}

    _db.execute('''
      CREATE TABLE IF NOT EXISTS arp_hosts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ip_address TEXT NOT NULL UNIQUE,
        ip_numeric INTEGER NOT NULL,
        mac_address TEXT NOT NULL,
        mac_clean TEXT NOT NULL,
        vendor TEXT NOT NULL,
        hostname TEXT,
        subnet TEXT NOT NULL,
        interface_name TEXT NOT NULL,
        status INTEGER NOT NULL,
        discovery_method TEXT NOT NULL,
        arp_type TEXT NOT NULL,
        rtt_ms REAL,
        ttl INTEGER,
        first_seen_ms INTEGER NOT NULL,
        last_seen_ms INTEGER NOT NULL,
        response_count INTEGER NOT NULL DEFAULT 1,
        conflicting_macs TEXT NOT NULL DEFAULT '[]',
        associated_ips TEXT NOT NULL DEFAULT '[]',
        notes TEXT NOT NULL DEFAULT '',
        raw_arp_line TEXT NOT NULL DEFAULT ''
      );

      CREATE INDEX IF NOT EXISTS idx_arp_ip_num ON arp_hosts(ip_numeric);
      CREATE INDEX IF NOT EXISTS idx_arp_mac ON arp_hosts(mac_address);
      CREATE INDEX IF NOT EXISTS idx_arp_mac_clean ON arp_hosts(mac_clean);
      CREATE INDEX IF NOT EXISTS idx_arp_vendor ON arp_hosts(vendor);
      CREATE INDEX IF NOT EXISTS idx_arp_status ON arp_hosts(status);
      CREATE INDEX IF NOT EXISTS idx_arp_last_seen ON arp_hosts(last_seen_ms);
    ''');
  }

  static String _cleanMacHex(String mac) {
    return mac.toUpperCase().replaceAll(RegExp(r'[^0-9A-F]'), '');
  }

  static bool _isValidResolvedMac(String mac) {
    final clean = _cleanMacHex(mac);
    return clean.length == 12 &&
        clean != '000000000000' &&
        clean != 'FFFFFFFFFFFF';
  }

  /// Upserts a batch of discovered host records into SQLite, performing automatic
  /// L2/L3 IP conflict detection when multiple MAC addresses claim the same IP.
  void upsertBatch(List<ArpHostRecord> records) {
    if (records.isEmpty) return;

    _db.execute('BEGIN TRANSACTION');
    try {
      var hasResolvedMacInBatch = false;
      for (final incoming in records) {
        if (_isValidResolvedMac(incoming.macAddress) ||
            incoming.conflictingMacs.any(_isValidResolvedMac)) {
          hasResolvedMacInBatch = true;
        }
        final existingRows = _db.select(
          'SELECT * FROM arp_hosts WHERE ip_address = ? LIMIT 1',
          [incoming.ipAddress],
        );

        final normalizedMac = _isValidResolvedMac(incoming.macAddress)
            ? ArpHostRecord.normalizeMac(incoming.macAddress)
            : incoming.macAddress;
        final cleanHex = _cleanMacHex(normalizedMac);

        if (existingRows.isEmpty) {
          final initialConflicts = <String>{
            ...incoming.conflictingMacs.map(ArpHostRecord.normalizeMac),
            if (_isValidResolvedMac(normalizedMac)) normalizedMac,
          }.toList();
          final allCleanHex = <String>{
            cleanHex,
            ...initialConflicts.map(_cleanMacHex),
          }.join(' ');

          final isConflict =
              incoming.status == HostStatus.conflict ||
              initialConflicts.length > 1;
          final effectiveStatus = isConflict
              ? HostStatus.conflict
              : incoming.status;
          final effectiveNotes = isConflict && incoming.notes.isEmpty
              ? _buildConflictNote(initialConflicts)
              : incoming.notes;

          _db.execute(
            '''
            INSERT INTO arp_hosts (
              ip_address, ip_numeric, mac_address, mac_clean, vendor,
              hostname, subnet, interface_name, status, discovery_method,
              arp_type, rtt_ms, ttl, first_seen_ms, last_seen_ms,
              response_count, conflicting_macs, associated_ips, notes, raw_arp_line
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''',
            [
              incoming.ipAddress,
              incoming.ipNumeric,
              normalizedMac,
              allCleanHex,
              incoming.vendor,
              incoming.hostname,
              incoming.subnet,
              incoming.interfaceName,
              effectiveStatus.code,
              incoming.discoveryMethod,
              incoming.arpType,
              incoming.rttMs,
              incoming.ttl,
              incoming.firstSeenMs,
              incoming.lastSeenMs,
              incoming.responseCount,
              jsonEncode(initialConflicts),
              jsonEncode(incoming.associatedIps),
              effectiveNotes,
              incoming.rawArpLine,
            ],
          );
        } else {
          final existing = ArpHostRecord.fromRow(existingRows.first);

          final mergedMacs = <String>{
            ...existing.conflictingMacs.map(ArpHostRecord.normalizeMac),
            if (_isValidResolvedMac(existing.macAddress))
              ArpHostRecord.normalizeMac(existing.macAddress),
            ...incoming.conflictingMacs.map(ArpHostRecord.normalizeMac),
            if (_isValidResolvedMac(normalizedMac)) normalizedMac,
          }.toList();

          final hasMacConflict =
              mergedMacs.length > 1 ||
              incoming.status == HostStatus.conflict ||
              existing.status == HostStatus.conflict;

          final finalMac = _isValidResolvedMac(normalizedMac)
              ? normalizedMac
              : existing.macAddress;
          final finalVendor = _isValidResolvedMac(normalizedMac)
              ? incoming.vendor
              : existing.vendor;
          final finalStatus = hasMacConflict
              ? HostStatus.conflict
              : (incoming.status == HostStatus.icmpOnly &&
                        _isValidResolvedMac(existing.macAddress)
                    ? HostStatus.online
                    : incoming.status);

          final finalDiscovery =
              (existing.discoveryMethod.contains('ARP') &&
                  incoming.discoveryMethod.contains('ICMP'))
              ? 'ARP + ICMP'
              : incoming.discoveryMethod;

          final finalNotes = hasMacConflict
              ? (incoming.notes.isNotEmpty
                    ? incoming.notes
                    : _buildConflictNote(mergedMacs))
              : (incoming.notes.isNotEmpty ? incoming.notes : existing.notes);

          final mergedCleanHex = <String>{
            _cleanMacHex(finalMac),
            ...mergedMacs.map(_cleanMacHex),
          }.join(' ');

          _db.execute(
            '''
            UPDATE arp_hosts SET
              mac_address = ?,
              mac_clean = ?,
              vendor = ?,
              hostname = COALESCE(?, hostname),
              subnet = ?,
              interface_name = ?,
              status = ?,
              discovery_method = ?,
              arp_type = ?,
              rtt_ms = COALESCE(?, rtt_ms),
              ttl = COALESCE(?, ttl),
              last_seen_ms = ?,
              response_count = response_count + 1,
              conflicting_macs = ?,
              notes = ?,
              raw_arp_line = CASE WHEN ? != '' THEN ? ELSE raw_arp_line END
            WHERE ip_address = ?
            ''',
            [
              finalMac,
              mergedCleanHex,
              finalVendor,
              incoming.hostname,
              incoming.subnet.isNotEmpty ? incoming.subnet : existing.subnet,
              incoming.interfaceName.isNotEmpty
                  ? incoming.interfaceName
                  : existing.interfaceName,
              finalStatus.code,
              finalDiscovery,
              incoming.arpType,
              incoming.rttMs,
              incoming.ttl,
              incoming.lastSeenMs,
              jsonEncode(mergedMacs),
              finalNotes,
              incoming.rawArpLine,
              incoming.rawArpLine,
              incoming.ipAddress,
            ],
          );
        }
      }

      if (hasResolvedMacInBatch) {
        _recomputeAssociatedIpsForSharedMacs();
      }
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }

    _enforceRetentionCap();
  }

  /// Cleans up temporary 'RESOLVING...' placeholders if a scan was cancelled mid-sweep.
  void cleanupCancelledSweep() {
    _db.execute(
      "DELETE FROM arp_hosts WHERE mac_address = 'RESOLVING...'",
    );
  }

  /// Reconciles table state after a full subnet sweep completes:
  /// removes any leftover 'RESOLVING...' placeholders and transitions previously active
  /// non-conflicting hosts in [subnet] that did not respond in [activeIps] to [HostStatus.stale].
  void reconcileSweepCompletion({
    required String subnet,
    required Set<String> activeIps,
    bool markMissingAsStale = true,
  }) {
    _db.execute('BEGIN TRANSACTION');
    try {
      _db.execute(
        "DELETE FROM arp_hosts WHERE mac_address = 'RESOLVING...'",
      );

      if (markMissingAsStale && subnet.isNotEmpty) {
        final rows = _db.select(
          'SELECT id, ip_address, status FROM arp_hosts WHERE subnet = ?',
          [subnet],
        );
        for (final row in rows) {
          final id = row['id'] as int;
          final ip = row['ip_address'] as String;
          final statusCode = row['status'] as int;
          if (!activeIps.contains(ip) &&
              statusCode != HostStatus.conflict.code &&
              statusCode != HostStatus.stale.code) {
            _db.execute(
              'UPDATE arp_hosts SET status = ? WHERE id = ?',
              [HostStatus.stale.code, id],
            );
          }
        }
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
    }
  }

  String _buildConflictNote(List<String> macs) {
    final formatted = macs
        .map((m) => '$m (${OuiLookupService.lookupVendor(m)})')
        .join(' vs ');
    return 'IP CONFLICT: Claimed by $formatted';
  }

  /// Correlates hosts sharing the same physical MAC address across different IPs,
  /// and clears stale multi-homed associations when a MAC only claims a single IP.
  void _recomputeAssociatedIpsForSharedMacs() {
    final rows = _db.select('''
      SELECT id, ip_address, mac_address, associated_ips
      FROM arp_hosts
      ORDER BY ip_numeric ASC
    ''');

    final macToIps = <String, List<String>>{};
    for (final row in rows) {
      final ip = row['ip_address'] as String;
      final mac = row['mac_address'] as String;
      if (_isValidResolvedMac(mac)) {
        macToIps.putIfAbsent(mac, () => []).add(ip);
      }
    }

    for (final row in rows) {
      final id = row['id'] as int;
      final mac = row['mac_address'] as String;
      final existingJson = row['associated_ips'] as String? ?? '[]';
      final sharedIps = macToIps[mac];

      if (sharedIps != null && sharedIps.length > 1) {
        final nextJson = jsonEncode(sharedIps);
        if (existingJson != nextJson) {
          _db.execute(
            'UPDATE arp_hosts SET associated_ips = ? WHERE id = ?',
            [nextJson, id],
          );
        }
      } else if (existingJson != '[]') {
        _db.execute(
          "UPDATE arp_hosts SET associated_ips = '[]' WHERE id = ?",
          [id],
        );
      }
    }
  }

  void _enforceRetentionCap() {
    if (maxRows <= 0) return;
    try {
      final cntResult = _db.select('SELECT COUNT(*) as cnt FROM arp_hosts');
      final currentCount = cntResult.first['cnt'] as int? ?? 0;
      if (currentCount > maxRows) {
        final excess = currentCount - maxRows;
        _db.execute(
          'DELETE FROM arp_hosts WHERE id IN (SELECT id FROM arp_hosts ORDER BY last_seen_ms ASC LIMIT ?)',
          [excess],
        );
      }
    } catch (_) {}
  }

  /// Query hosts with pagination, sorting, and multi-field search filters.
  List<ArpHostRecord> queryHosts({
    int offset = 0,
    int limit = 1000,
    required ArpFilterCriteria filter,
  }) {
    final (whereClause, params) = _buildWhereClause(filter);

    const allowedSortColumns = {
      'id': 'id',
      'ip_numeric': 'ip_numeric',
      'mac_address': 'mac_address',
      'vendor': 'vendor',
      'hostname': 'hostname',
      'status': 'status',
      'rtt_ms': 'rtt_ms',
      'ttl': 'ttl',
      'last_seen_ms': 'last_seen_ms',
      'discovery_method': 'discovery_method',
    };
    final sortCol = allowedSortColumns[filter.sortColumn] ?? 'ip_numeric';
    final sortDirection = filter.sortAscending ? 'ASC' : 'DESC';

    final sql = StringBuffer('SELECT * FROM arp_hosts');
    if (whereClause.isNotEmpty) {
      sql.write(' WHERE $whereClause');
    }
    sql.write(
      ' ORDER BY $sortCol $sortDirection, ip_numeric ASC LIMIT ? OFFSET ?',
    );
    params.addAll([limit, offset]);

    final result = _db.select(sql.toString(), params);
    return result.map((row) => ArpHostRecord.fromRow(row)).toList();
  }

  /// Total count of hosts matching active filter.
  int countHosts(ArpFilterCriteria filter) {
    final (whereClause, params) = _buildWhereClause(filter);
    final sql = StringBuffer('SELECT COUNT(*) as count FROM arp_hosts');
    if (whereClause.isNotEmpty) {
      sql.write(' WHERE $whereClause');
    }
    final result = _db.select(sql.toString(), params);
    if (result.isEmpty) return 0;
    return result.first['count'] as int? ?? 0;
  }

  /// Total count of all hosts in the database (unfiltered).
  int totalUnfilteredCount() {
    final result = _db.select('SELECT COUNT(*) as count FROM arp_hosts');
    if (result.isEmpty) return 0;
    return result.first['count'] as int? ?? 0;
  }

  /// Status counts for quick filter chips and conflict alert banner.
  Map<HostStatus, int> getStatusCounts() {
    final counts = <HostStatus, int>{
      for (final s in HostStatus.values) s: 0,
    };
    final result = _db.select('''
      SELECT status, COUNT(*) as count
      FROM arp_hosts
      GROUP BY status
    ''');
    for (final row in result) {
      final code = row['status'] as int;
      final count = row['count'] as int;
      final status = HostStatus.fromCode(code);
      counts[status] = count;
    }
    return counts;
  }

  void clearAll() {
    _db.execute('DELETE FROM arp_hosts');
    try {
      _db.execute("DELETE FROM sqlite_sequence WHERE name = 'arp_hosts'");
    } catch (_) {}
  }

  static String _escapeLike(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  (String, List<Object?>) _buildWhereClause(ArpFilterCriteria filter) {
    final clauses = <String>[];
    final params = <Object?>[];

    // Unified search query across IP, MAC (formatted or hex-only), Vendor, Hostname, Notes, and Conflicting MACs
    if (filter.searchQuery.trim().isNotEmpty) {
      final raw = filter.searchQuery.trim();
      final q = '%${_escapeLike(raw)}%';
      final cleanHex = _cleanMacHex(raw);
      if (cleanHex.isNotEmpty && cleanHex.length >= 2) {
        final hexQuery = '%$cleanHex%';
        clauses.add(
          "(ip_address LIKE ? ESCAPE '\\' OR mac_address LIKE ? ESCAPE '\\' OR mac_clean LIKE ? OR conflicting_macs LIKE ? ESCAPE '\\' OR vendor LIKE ? ESCAPE '\\' OR hostname LIKE ? ESCAPE '\\' OR notes LIKE ? ESCAPE '\\')",
        );
        params.addAll([q, q, hexQuery, q, q, q, q]);
      } else {
        clauses.add(
          "(ip_address LIKE ? ESCAPE '\\' OR mac_address LIKE ? ESCAPE '\\' OR conflicting_macs LIKE ? ESCAPE '\\' OR vendor LIKE ? ESCAPE '\\' OR hostname LIKE ? ESCAPE '\\' OR notes LIKE ? ESCAPE '\\')",
        );
        params.addAll([q, q, q, q, q, q]);
      }
    }

    // Dedicated IP Address / Subnet filter
    if (filter.ipFilter.trim().isNotEmpty) {
      final q = '%${_escapeLike(filter.ipFilter.trim())}%';
      clauses.add("(ip_address LIKE ? ESCAPE '\\' OR subnet LIKE ? ESCAPE '\\')");
      params.addAll([q, q]);
    }

    // Dedicated MAC Address / OUI filter (handles :, -, ., or raw hex seamlessly)
    if (filter.macFilter.trim().isNotEmpty) {
      final rawMac = filter.macFilter.trim();
      final q = '%${_escapeLike(rawMac)}%';
      final cleanHex = _cleanMacHex(rawMac);
      if (cleanHex.isNotEmpty) {
        clauses.add(
          "(mac_address LIKE ? ESCAPE '\\' OR mac_clean LIKE ? OR conflicting_macs LIKE ? ESCAPE '\\')",
        );
        params.addAll([q, '%$cleanHex%', q]);
      } else {
        clauses.add(
          "(mac_address LIKE ? ESCAPE '\\' OR conflicting_macs LIKE ? ESCAPE '\\')",
        );
        params.addAll([q, q]);
      }
    }

    // Vendor filter
    if (filter.vendorFilter.trim().isNotEmpty) {
      final q = '%${_escapeLike(filter.vendorFilter.trim())}%';
      clauses.add("vendor LIKE ? ESCAPE '\\'");
      params.add(q);
    }

    // Conflicts only toggle
    if (filter.conflictsOnly) {
      clauses.add('status = ?');
      params.add(HostStatus.conflict.code);
    } else if (filter.selectedStatuses.isNotEmpty &&
        filter.selectedStatuses.length < HostStatus.values.length) {
      final placeholders = List.filled(filter.selectedStatuses.length, '?').join(',');
      clauses.add('status IN ($placeholders)');
      params.addAll(filter.selectedStatuses.map((s) => s.code));
    }

    return (clauses.join(' AND '), params);
  }

  void close() {
    _db.close();
  }
}
