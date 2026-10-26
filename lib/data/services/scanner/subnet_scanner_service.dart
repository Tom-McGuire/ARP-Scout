import 'dart:async';
import 'dart:io';
import '../../../domain/models/arp_host_record.dart';
import '../../../domain/models/host_status.dart';
import '../oui/oui_lookup_service.dart';

class IcmpProbeResult {
  const IcmpProbeResult({
    required this.ip,
    required this.reachable,
    this.rttMs,
    this.ttl,
  });

  final String ip;
  final bool reachable;
  final double? rttMs;
  final int? ttl;
}

class ParsedArpEntry {
  const ParsedArpEntry({
    required this.ipAddress,
    required this.macAddress,
    required this.arpType,
    required this.interfaceIp,
    required this.rawLine,
  });

  final String ipAddress;
  final String macAddress;
  final String arpType;
  final String interfaceIp;
  final String rawLine;
}

class SubnetScannerService {
  bool _isCancelled = false;
  final Set<Process> _activeProcesses = {};

  bool get isCancelled => _isCancelled;

  /// Cancels any active scan and terminates running child CLI processes.
  Future<void> cancelActiveScan() async {
    _isCancelled = true;
    final procs = _activeProcesses.toList();
    _activeProcesses.clear();
    for (final p in procs) {
      try {
        p.kill();
      } catch (_) {}
    }
  }

  /// Resolves a system networking binary using absolute System32 paths on Windows
  /// to prevent current-working-directory DLL/binary hijacking.
  static String _resolveSystemBinary(String binaryName) {
    if (Platform.isWindows) {
      final sysRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final candidate = '$sysRoot\\System32\\$binaryName.exe';
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return binaryName;
  }

  /// Validates that [input] is a safe, well-formed CIDR, IP range, or IPv4 address.
  static bool isValidTargetSpecification(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    if (!RegExp(r'^[0-9./-]+$').hasMatch(trimmed)) return false;
    return expandTargetSubnet(trimmed, maxHosts: 1).isNotEmpty;
  }

  /// Generates a sanitized preview CLI command string for the inspector / toolbar.
  static String buildCliPreviewCommand(String subnetCidr, {bool arpOnly = false}) {
    final safeTarget = isValidTargetSpecification(subnetCidr)
        ? subnetCidr.trim()
        : '192.168.1.0/24';

    if (Platform.isWindows) {
      if (arpOnly) return 'arp -a';
      return 'for /L %i in (1,1,254) do @start /b ping -n 1 -w 250 ${_basePrefix(safeTarget)}.%i >nul & arp -a';
    } else {
      if (arpOnly) return 'ip neigh show || arp -an';
      return 'fping -a -g $safeTarget 2>/dev/null; arp -an';
    }
  }

  static String _basePrefix(String cidr) {
    final ipPart = cidr.split('/').first.split('-').first.trim();
    if (ArpHostRecord.isValidIpv4(ipPart)) {
      final parts = ipPart.split('.');
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return '192.168.1';
  }

  /// Checks whether [ip] belongs to [targetSubnet] (supporting arbitrary CIDR prefixes `/16`..`/32`,
  /// explicit ranges, or single IPs).
  static bool isIpInTargetSubnet(
    String ip,
    String targetSubnet,
    Set<String> expandedTargetIps,
  ) {
    if (!ArpHostRecord.isValidIpv4(ip)) return false;
    if (expandedTargetIps.contains(ip)) return true;

    final trimmed = targetSubnet.trim();
    if (trimmed.contains('/')) {
      final parts = trimmed.split('/');
      if (parts.length != 2) return false;
      final baseIp = parts[0].trim();
      final prefix = int.tryParse(parts[1].trim());
      if (!ArpHostRecord.isValidIpv4(baseIp) ||
          prefix == null ||
          prefix < 16 ||
          prefix > 32) {
        return false;
      }
      if (prefix == 32) return ip == baseIp;
      final hostBits = 32 - prefix;
      final mask = (0xFFFFFFFF << hostBits) & 0xFFFFFFFF;
      final ipNum = ArpHostRecord.ipv4ToInt(ip);
      final netNum = ArpHostRecord.ipv4ToInt(baseIp) & mask;
      final bcastNum = netNum | ((1 << hostBits) - 1);
      if (prefix <= 30 && (ipNum == netNum || ipNum == bcastNum)) {
        return false;
      }
      return (ipNum & mask) == netNum;
    }

    return false;
  }

  /// Parses a CIDR (e.g. 192.168.1.0/24), IP range (192.168.1.1-192.168.1.50 or 192.168.1.1-50),
  /// or single IPv4 address into a list of host IPv4 addresses to probe (capped at [maxHosts]).
  static List<String> expandTargetSubnet(String input, {int maxHosts = 1024}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return const [];

    // 1. Check CIDR notation: a.b.c.d/prefix
    if (trimmed.contains('/')) {
      final parts = trimmed.split('/');
      if (parts.length != 2) return const [];
      final baseIp = parts[0].trim();
      final prefix = int.tryParse(parts[1].trim());
      if (!ArpHostRecord.isValidIpv4(baseIp) ||
          prefix == null ||
          prefix < 16 ||
          prefix > 32) {
        return const [];
      }
      final ipNum = ArpHostRecord.ipv4ToInt(baseIp);
      if (ipNum == 0 && baseIp != '0.0.0.0') return const [];

      if (prefix == 32) return [baseIp];
      final hostBits = 32 - prefix;
      final mask = (0xFFFFFFFF << hostBits) & 0xFFFFFFFF;
      final network = ipNum & mask;
      final broadcast = network | ((1 << hostBits) - 1);

      final startIp = prefix >= 31 ? network : network + 1;
      final endIp = prefix >= 31 ? broadcast : broadcast - 1;
      final count = (endIp - startIp + 1).clamp(0, maxHosts);

      return List<String>.generate(
        count,
        (i) => ArpHostRecord.intToIpv4(startIp + i),
      );
    }

    // 2. Check range notation: 192.168.1.1-192.168.1.100 or 192.168.1.1-50
    if (trimmed.contains('-')) {
      final parts = trimmed.split('-');
      if (parts.length != 2) return const [];
      final startStr = parts[0].trim();
      final endStr = parts[1].trim();
      if (!ArpHostRecord.isValidIpv4(startStr)) return const [];
      final startNum = ArpHostRecord.ipv4ToInt(startStr);
      if (startNum == 0) return const [];

      int endNum;
      if (endStr.contains('.')) {
        if (!ArpHostRecord.isValidIpv4(endStr)) return const [];
        endNum = ArpHostRecord.ipv4ToInt(endStr);
      } else {
        final lastOctet = int.tryParse(endStr);
        if (lastOctet == null || lastOctet < 0 || lastOctet > 255) {
          return const [];
        }
        final octets = startStr.split('.');
        endNum = ArpHostRecord.ipv4ToInt(
          '${octets[0]}.${octets[1]}.${octets[2]}.$lastOctet',
        );
      }

      if (endNum < startNum) return const [];
      final count = (endNum - startNum + 1).clamp(0, maxHosts);
      return List<String>.generate(
        count,
        (i) => ArpHostRecord.intToIpv4(startNum + i),
      );
    }

    // 3. Single IPv4 address
    if (ArpHostRecord.isValidIpv4(trimmed)) {
      return [trimmed];
    }

    return const [];
  }

  /// Parses cross-platform `arp -a` / `arp -an` / `ip neigh` output into structured L2 entries.
  static List<ParsedArpEntry> parseArpTableOutput(String rawOutput) {
    final entries = <ParsedArpEntry>[];
    var currentInterface = 'System ARP';

    final lines = rawOutput.split(RegExp(r'\r?\n'));
    // Windows Interface header (locale-independent via `--- 0x...` or `Interface:`):
    // e.g. "Interface: 192.168.1.25 --- 0xe" or "Schnittstelle: 192.168.1.25 --- 0xe"
    final winIfaceRegex = RegExp(
      r'(?:Interface:\s*(\d{1,3}(?:\.\d{1,3}){3})|(\d{1,3}(?:\.\d{1,3}){3})\s+---\s+0x[0-9a-fA-F]+)',
      caseSensitive: false,
    );
    // Windows ARP entry: 192.168.1.1   00-1b-54-11-22-33   dynamic
    final winEntryRegex = RegExp(
      r'^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){5})\s+(\S+)',
    );
    // Unix/macOS `arp -an` entry: ? (192.168.1.1) at 00:1b:54:11:22:33 [ether] on en0
    final unixArpRegex = RegExp(
      r'\((\d{1,3}(?:\.\d{1,3}){3})\)\s+at\s+([0-9a-fA-F]{1,2}(?::[0-9a-fA-F]{1,2}){5})\s+.*?on\s+(\S+)',
      caseSensitive: false,
    );
    // Linux `ip neigh` entry: 192.168.1.1 dev eth0 lladdr 00:1b:54:11:22:33 REACHABLE
    final ipNeighRegex = RegExp(
      r'^(\d{1,3}(?:\.\d{1,3}){3})\s+(?:dev\s+(\S+)\s+)?lladdr\s+([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})\s+(\S+)',
      caseSensitive: false,
    );

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final ifaceMatch = winIfaceRegex.firstMatch(trimmed);
      if (ifaceMatch != null) {
        final candidateIp = ifaceMatch.group(1) ?? ifaceMatch.group(2);
        if (candidateIp != null && ArpHostRecord.isValidIpv4(candidateIp)) {
          currentInterface = candidateIp;
          continue;
        }
      }

      final winMatch = winEntryRegex.firstMatch(line);
      if (winMatch != null) {
        final ip = winMatch.group(1)!;
        final mac = ArpHostRecord.normalizeMac(winMatch.group(2)!);
        final rawType = winMatch.group(3)!.toLowerCase();
        final type = _normalizeArpType(rawType);
        if (ArpHostRecord.isValidIpv4(ip) &&
            !_isIgnoredBroadcastOrMulticast(ip, mac)) {
          entries.add(
            ParsedArpEntry(
              ipAddress: ip,
              macAddress: mac,
              arpType: type,
              interfaceIp: currentInterface,
              rawLine: trimmed,
            ),
          );
        }
        continue;
      }

      final unixMatch = unixArpRegex.firstMatch(line);
      if (unixMatch != null) {
        final ip = unixMatch.group(1)!;
        final mac = _normalizeVariableHexMac(unixMatch.group(2)!);
        final dev = unixMatch.group(3)!;
        if (ArpHostRecord.isValidIpv4(ip) &&
            !_isIgnoredBroadcastOrMulticast(ip, mac)) {
          entries.add(
            ParsedArpEntry(
              ipAddress: ip,
              macAddress: mac,
              arpType: line.contains('permanent') ? 'static' : 'dynamic',
              interfaceIp: dev,
              rawLine: trimmed,
            ),
          );
        }
        continue;
      }

      final neighMatch = ipNeighRegex.firstMatch(line);
      if (neighMatch != null) {
        final ip = neighMatch.group(1)!;
        final dev = neighMatch.group(2) ?? currentInterface;
        final mac = ArpHostRecord.normalizeMac(neighMatch.group(3)!);
        final state = neighMatch.group(4)!.toLowerCase();
        if (ArpHostRecord.isValidIpv4(ip) &&
            !_isIgnoredBroadcastOrMulticast(ip, mac)) {
          entries.add(
            ParsedArpEntry(
              ipAddress: ip,
              macAddress: mac,
              arpType: state,
              interfaceIp: dev,
              rawLine: trimmed,
            ),
          );
        }
      }
    }

    return entries;
  }

  static String _normalizeArpType(String rawType) {
    if (rawType.contains('dyn')) return 'dynamic';
    if (rawType.contains('stat') || rawType.contains('perm')) return 'static';
    return rawType;
  }

  static String _normalizeVariableHexMac(String raw) {
    final parts = raw.split(RegExp(r'[:-]'));
    if (parts.length != 6) return ArpHostRecord.normalizeMac(raw);
    return parts
        .map((p) => p.padLeft(2, '0').toUpperCase())
        .join(':');
  }

  static bool _isIgnoredBroadcastOrMulticast(String ip, String mac) {
    if (mac == 'FF:FF:FF:FF:FF:FF' || mac == '00:00:00:00:00:00') {
      return true;
    }
    if (mac.startsWith('01:00:5E')) {
      return true;
    }
    final octets = ip.split('.');
    if (octets.length != 4) return true;
    final first = int.tryParse(octets[0]) ?? 0;
    final last = int.tryParse(octets[3]) ?? 0;
    // Ignore multicast (224.0.0.0 - 239.255.255.255), loopback (127.x), and .255 broadcast
    if (first >= 224 || first == 127 || last == 255 || last == 0) {
      return true;
    }
    return false;
  }

  /// Reads the local operating system ARP table (`arp -a` on Windows, `ip neigh` / `arp -an` on Linux/macOS).
  Future<List<ParsedArpEntry>> readSystemArpCache() async {
    if (Platform.isLinux) {
      try {
        final ipNeighResult = await Process.run('ip', const ['neigh', 'show']);
        if (ipNeighResult.exitCode == 0) {
          final parsed = parseArpTableOutput(ipNeighResult.stdout.toString());
          if (parsed.isNotEmpty) return parsed;
        }
      } catch (_) {}
    }

    try {
      final arpBin = _resolveSystemBinary('arp');
      final result = await Process.run(
        arpBin,
        Platform.isWindows ? const ['-a'] : const ['-an'],
      );
      if (result.exitCode == 0) {
        return parseArpTableOutput(result.stdout.toString());
      }
    } catch (_) {}
    return const [];
  }

  /// Executes a single fast ICMP echo probe to trigger kernel ARP resolution and measure RTT/TTL.
  Future<IcmpProbeResult> probeHostIcmp(String ip, {int timeoutMs = 300}) async {
    if (_isCancelled || !ArpHostRecord.isValidIpv4(ip)) {
      return IcmpProbeResult(ip: ip, reachable: false);
    }

    Process? proc;
    try {
      final pingBin = _resolveSystemBinary('ping');
      final args = Platform.isWindows
          ? ['-n', '1', '-w', '$timeoutMs', ip]
          : [
              '-c',
              '1',
              '-W',
              Platform.isMacOS ? '$timeoutMs' : '1',
              ip,
            ];

      final sw = Stopwatch()..start();
      proc = await Process.start(pingBin, args);
      _activeProcesses.add(proc);

      final stdoutFuture = proc.stdout.transform(const SystemEncoding().decoder).join();
      final exitCode = await proc.exitCode.timeout(
        Duration(milliseconds: timeoutMs + 700),
        onTimeout: () {
          proc?.kill();
          return -1;
        },
      );
      sw.stop();
      _activeProcesses.remove(proc);

      if (_isCancelled || exitCode != 0) {
        return IcmpProbeResult(ip: ip, reachable: false);
      }

      final output = await stdoutFuture;
      // Verify output contains TTL= or ttl= (since Windows ping returns exitCode 0 even on "Destination host unreachable" from local gateway!)
      final ttlMatch = RegExp(r'ttl[=<](\d+)', caseSensitive: false).firstMatch(output);
      if (ttlMatch == null) {
        return IcmpProbeResult(ip: ip, reachable: false);
      }

      final ttl = int.tryParse(ttlMatch.group(1)!);
      final timeMatch = RegExp(
        r'time[=<](\d+(?:\.\d+)?)\s*ms',
        caseSensitive: false,
      ).firstMatch(output);

      final rtt = timeMatch != null
          ? double.tryParse(timeMatch.group(1)!)
          : sw.elapsedMilliseconds.toDouble();

      return IcmpProbeResult(
        ip: ip,
        reachable: true,
        rttMs: rtt,
        ttl: ttl,
      );
    } catch (_) {
      if (proc != null) {
        _activeProcesses.remove(proc);
      }
      return IcmpProbeResult(ip: ip, reachable: false);
    }
  }

  /// Performs a complete L2 ARP + L3 ICMP subnet sweep with live progress callbacks.
  Future<List<ArpHostRecord>> performSubnetSweep({
    required String targetSubnet,
    required String interfaceName,
    String? localInterfaceIp,
    bool arpCacheOnly = false,
    int concurrency = 32,
    void Function(int probed, int total, String phase, List<ArpHostRecord> partialBatch)?
    onProgress,
  }) async {
    _isCancelled = false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final targetIps = arpCacheOnly
        ? <String>[]
        : expandTargetSubnet(targetSubnet);

    final icmpResults = <String, IcmpProbeResult>{};

    // Phase 1: Concurrent L3 ICMP Ping Sweep (populates OS L2 ARP table & measures RTT/TTL)
    if (!arpCacheOnly && targetIps.isNotEmpty) {
      var completed = 0;
      final total = targetIps.length;
      onProgress?.call(0, total, 'L3 ICMP Sweep (Populating ARP Cache)...', const []);

      for (var i = 0; i < targetIps.length; i += concurrency) {
        if (_isCancelled) break;
        final end = (i + concurrency < targetIps.length)
            ? i + concurrency
            : targetIps.length;
        final chunk = targetIps.sublist(i, end);

        final chunkResults = await Future.wait(
          chunk.map((ip) => probeHostIcmp(ip, timeoutMs: 280)),
        );

        final immediateHits = <ArpHostRecord>[];
        for (final res in chunkResults) {
          completed++;
          if (res.reachable) {
            icmpResults[res.ip] = res;
            immediateHits.add(
              ArpHostRecord(
                ipAddress: res.ip,
                ipNumeric: ArpHostRecord.ipv4ToInt(res.ip),
                macAddress: 'RESOLVING...',
                vendor: 'Resolving L2 ARP...',
                subnet: targetSubnet,
                interfaceName: interfaceName,
                status: HostStatus.icmpOnly,
                discoveryMethod: 'ICMP Echo',
                rttMs: res.rttMs,
                ttl: res.ttl,
                firstSeenMs: nowMs,
                lastSeenMs: nowMs,
              ),
            );
          }
        }

        onProgress?.call(
          completed,
          total,
          'L3 ICMP Sweep ($completed/$total probed)...',
          immediateHits,
        );
      }
    }

    if (_isCancelled) return const [];

    // Phase 2: Read OS L2 ARP Cache (`arp -a` / `ip neigh`)
    onProgress?.call(
      targetIps.length,
      targetIps.length,
      'Reading L2 ARP Table & Resolving OUI Vendors...',
      const [],
    );

    final arpEntries = await readSystemArpCache();

    // Group ARP entries by IP to detect multi-MAC conflicts for the same IP
    final arpByIp = <String, List<ParsedArpEntry>>{};
    for (final entry in arpEntries) {
      arpByIp.putIfAbsent(entry.ipAddress, () => []).add(entry);
    }

    final targetIpSet = targetIps.toSet();
    final candidateIpList = <String>{
      ...icmpResults.keys,
      ...arpByIp.keys.where((ip) {
        if (arpCacheOnly || targetIpSet.isEmpty) return true;
        return isIpInTargetSubnet(ip, targetSubnet, targetIpSet);
      }),
    }.toList();

    // Resolve reverse DNS concurrently in batches rather than sequentially per host
    final hostnamesByIp = <String, String?>{};
    for (var i = 0; i < candidateIpList.length; i += concurrency) {
      if (_isCancelled) break;
      final end = (i + concurrency < candidateIpList.length)
          ? i + concurrency
          : candidateIpList.length;
      final batch = candidateIpList.sublist(i, end);
      final resolved = await Future.wait(
        batch.map((ip) async => MapEntry(ip, await _tryReverseDns(ip))),
      );
      for (final entry in resolved) {
        hostnamesByIp[entry.key] = entry.value;
      }
    }

    if (_isCancelled) return const [];

    final records = <ArpHostRecord>[];

    for (final ip in candidateIpList) {
      if (_isCancelled) break;
      final l2List = arpByIp[ip] ?? const [];
      final l3 = icmpResults[ip];

      final distinctMacs = l2List
          .map((e) => e.macAddress)
          .where((m) => m.isNotEmpty)
          .toSet()
          .toList();

      final primaryMac = distinctMacs.isNotEmpty
          ? distinctMacs.first
          : (ip == localInterfaceIp ? 'LOCAL INTERFACE' : 'UNRESOLVED');
      final vendor = distinctMacs.isNotEmpty
          ? OuiLookupService.lookupVendor(primaryMac)
          : (ip == localInterfaceIp
                ? 'Local Host Interface'
                : 'Unresolved (L3 Routed / No ARP)');

      HostStatus status;
      String method;
      if (distinctMacs.length > 1) {
        status = HostStatus.conflict;
        method = l3 != null ? 'ARP + ICMP (Conflict)' : 'ARP Table (Conflict)';
      } else if (distinctMacs.isNotEmpty && l3 != null) {
        status = HostStatus.online;
        method = 'ARP + ICMP';
      } else if (distinctMacs.isNotEmpty) {
        status = HostStatus.arpOnly;
        method = 'ARP Cache';
      } else {
        status = HostStatus.icmpOnly;
        method = 'ICMP Sweep';
      }

      records.add(
        ArpHostRecord(
          ipAddress: ip,
          ipNumeric: ArpHostRecord.ipv4ToInt(ip),
          macAddress: primaryMac,
          vendor: vendor,
          hostname: hostnamesByIp[ip],
          subnet: targetSubnet,
          interfaceName: l2List.isNotEmpty
              ? '$interfaceName (${l2List.first.interfaceIp})'
              : interfaceName,
          status: status,
          discoveryMethod: method,
          arpType: l2List.isNotEmpty ? l2List.first.arpType : 'dynamic',
          rttMs: l3?.rttMs,
          ttl: l3?.ttl,
          firstSeenMs: nowMs,
          lastSeenMs: nowMs,
          conflictingMacs: distinctMacs,
          rawArpLine: l2List.map((e) => e.rawLine).join('\n'),
        ),
      );
    }

    return records;
  }

  Future<String?> _tryReverseDns(String ip) async {
    try {
      final addr = InternetAddress(ip);
      final rev = await addr.reverse().timeout(
        const Duration(milliseconds: 120),
      );
      if (rev.host.isNotEmpty && rev.host != ip) {
        return rev.host;
      }
    } catch (_) {}
    return null;
  }
}
