import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../../domain/models/arp_host_record.dart';

/// Result of a passive L2/L3 control-frame capture window.
class L2RoleSniffResult {
  const L2RoleSniffResult({
    this.stpRootMac,
    this.stpRootPriority,
    this.igmpQuerierIp,
    this.igmpQuerierVersion,
  });

  static const empty = L2RoleSniffResult();

  /// Normalized (AA:BB:CC:DD:EE:FF) Root Bridge system MAC.
  final String? stpRootMac;
  final int? stpRootPriority;
  final String? igmpQuerierIp;

  /// "IGMPv2" or "IGMPv3".
  final String? igmpQuerierVersion;

  bool get isEmpty => stpRootMac == null && igmpQuerierIp == null;

  /// True when both roles were observed but resolve to different hosts.
  bool rolesOnDifferentHosts(Iterable<ArpHostRecord> hosts) {
    if (stpRootMac == null || igmpQuerierIp == null) return false;
    ArpHostRecord? root;
    ArpHostRecord? querier;
    for (final h in hosts) {
      if (h.isStpRootBridge) root = h;
      if (h.isIgmpQuerier) querier = h;
    }
    if (root == null || querier == null) return false;
    return ArpHostRecord.normalizeMac(root.macAddress) !=
        ArpHostRecord.normalizeMac(querier.macAddress);
  }
}

/// Passive listener for STP BPDUs and IGMP General Queries.
///
/// Dart has no raw-socket API, so capture is delegated to `tcpdump` (Linux /
/// macOS, typically requires capture privileges) or Wireshark's `tshark` as a
/// fallback. If capture is unavailable
/// the service returns [L2RoleSniffResult.empty] and never throws.
class L2RoleSnifferService {
  L2RoleSnifferService({
    this.captureWindow = const Duration(seconds: 4),
    this.igmpListenWindow = const Duration(seconds: 130),
  });

  /// Short window used right after a sweep (catches STP hellos, sent ~2s).
  final Duration captureWindow;

  /// Long window for IGMP General Queries (default interval is 60–125s).
  final Duration igmpListenWindow;

  static const _bpduDstMac = '01:80:c2:00:00:00';
  static const _stpAndIgmpFilter =
      'ether dst $_bpduDstMac or (dst host 224.0.0.1 and igmp)';
  static const _igmpFilter = 'dst host 224.0.0.1 and igmp';

  Process? _igmpProc;
  Completer<void>? _igmpCancel;

  /// Short STP + IGMP capture.
  Future<L2RoleSniffResult> sniff({required String interfaceName}) {
    return _run(interfaceName, _stpAndIgmpFilter, captureWindow);
  }

  /// Long, cancellable IGMP-only listen. Ends early once a query is seen.
  Future<L2RoleSniffResult> listenForIgmpQuerier({
    required String interfaceName,
  }) async {
    cancelIgmpListen();
    final cancel = Completer<void>();
    _igmpCancel = cancel;
    try {
      return await _run(
        interfaceName,
        _igmpFilter,
        igmpListenWindow,
        cancel: cancel,
        stopWhenFound: true,
        onProcess: (p) => _igmpProc = p,
      );
    } finally {
      if (identical(_igmpCancel, cancel)) {
        _igmpCancel = null;
        _igmpProc = null;
      }
    }
  }

  /// Aborts a running [listenForIgmpQuerier].
  void cancelIgmpListen() {
    final c = _igmpCancel;
    if (c != null && !c.isCompleted) c.complete();
    _igmpProc?.kill(ProcessSignal.sigint);
  }

  Future<L2RoleSniffResult> _run(
    String interfaceName,
    String filter,
    Duration window, {
    Completer<void>? cancel,
    bool stopWhenFound = false,
    void Function(Process)? onProcess,
  }) async {
    if (interfaceName.isEmpty || Platform.isWindows) {
      return L2RoleSniffResult.empty;
    }
    // Try tcpdump first, then fall back to Wireshark's tshark.
    final tools = <(String, List<String>, List<Uint8List> Function(String))>[
      (
        'tcpdump',
        ['-i', interfaceName, '-nn', '-l', '-xx', '-s', '128', filter],
        parseTcpdumpHex,
      ),
      (
        'tshark',
        ['-i', interfaceName, '-n', '-l', '-x', '-s', '128', '-f', filter],
        parseTsharkHex,
      ),
    ];
    for (final (exe, args, parser) in tools) {
      if (cancel != null && cancel.isCompleted) break;
      final output = await _capture(
        exe,
        args,
        window,
        cancel: cancel,
        onProcess: onProcess,
        stopWhen: stopWhenFound
            ? (text) => parseFrames(parser(text)).igmpQuerierIp != null
            : null,
      );
      if (output == null) continue; // not installed / no privileges
      return parseFrames(parser(output));
    }
    return L2RoleSniffResult.empty;
  }

  /// Runs [exe] for [window]; returns stdout, or null if the tool could not be
  /// started or exited early with an error (e.g. missing privileges).
  Future<String?> _capture(
    String exe,
    List<String> args,
    Duration window, {
    Completer<void>? cancel,
    void Function(Process)? onProcess,
    bool Function(String)? stopWhen,
  }) async {
    Process? proc;
    try {
      proc = await Process.start(exe, args);
      onProcess?.call(proc);
      final buffer = StringBuffer();
      final done = Completer<void>();
      final sub = proc.stdout.transform(utf8.decoder).listen((chunk) {
        buffer.write(chunk);
        if (stopWhen != null &&
            !done.isCompleted &&
            stopWhen(buffer.toString())) {
          done.complete();
        }
      });
      unawaited(proc.stderr.drain<void>());
      var exited = false;
      int? exitCode;
      unawaited(
        proc.exitCode.then((c) {
          exited = true;
          exitCode = c;
          if (!done.isCompleted) done.complete();
        }),
      );
      await Future.any([
        Future<void>.delayed(window),
        done.future,
        if (cancel != null) cancel.future,
      ]);
      if (exited && exitCode != 0 && !(cancel?.isCompleted ?? false)) {
        await sub.cancel();
        return null;
      }
      proc.kill(ProcessSignal.sigint);
      await proc.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () {
          proc?.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      await sub.cancel();
      return buffer.toString();
    } catch (_) {
      proc?.kill(ProcessSignal.sigkill);
      return null;
    }
  }

  /// Parses `tshark -x` output (`0000  01 80 c2 ...  ascii`) into raw frames.
  static List<Uint8List> parseTsharkHex(String output) {
    final frames = <Uint8List>[];
    List<int>? current;
    final lineRe = RegExp(r'^([0-9a-fA-F]{4})  ');
    for (final line in const LineSplitter().convert(output)) {
      final m = lineRe.firstMatch(line);
      if (m == null) continue;
      if (m.group(1) == '0000') {
        if (current != null && current.isNotEmpty) {
          frames.add(Uint8List.fromList(current));
        }
        current = <int>[];
      }
      if (current == null) continue;
      final end = line.length < 54 ? line.length : 54;
      for (final tok in line.substring(6, end).trim().split(RegExp(r'\s+'))) {
        if (RegExp(r'^[0-9a-fA-F]{2}$').hasMatch(tok)) {
          current.add(int.parse(tok, radix: 16));
        }
      }
    }
    if (current != null && current.isNotEmpty) {
      frames.add(Uint8List.fromList(current));
    }
    return frames;
  }

  /// Parses `tcpdump -xx` text output into raw frames (one per packet).
  static List<Uint8List> parseTcpdumpHex(String output) {
    final frames = <Uint8List>[];
    List<int>? current;
    for (final line in const LineSplitter().convert(output)) {
      if (line.isEmpty) continue;
      final isHexLine = line.startsWith(RegExp(r'\s')) && line.contains('0x');
      if (!isHexLine) {
        if (current != null && current.isNotEmpty) {
          frames.add(Uint8List.fromList(current));
        }
        current = <int>[];
        continue;
      }
      final colon = line.indexOf(':');
      if (colon < 0 || current == null) continue;
      for (final group
          in line.substring(colon + 1).trim().split(RegExp(r'\s+'))) {
        if (group.length.isEven && RegExp(r'^[0-9a-fA-F]+$').hasMatch(group)) {
          for (var i = 0; i < group.length; i += 2) {
            current.add(int.parse(group.substring(i, i + 2), radix: 16));
          }
        }
      }
    }
    if (current != null && current.isNotEmpty) {
      frames.add(Uint8List.fromList(current));
    }
    return frames;
  }

  /// Reduces captured frames to the first BPDU root and IGMP querier seen.
  static L2RoleSniffResult parseFrames(Iterable<Uint8List> frames) {
    String? rootMac;
    int? rootPriority;
    String? querierIp;
    String? querierVersion;
    for (final f in frames) {
      if (rootMac == null) {
        final bpdu = parseBpdu(f);
        if (bpdu != null) {
          rootMac = bpdu.mac;
          rootPriority = bpdu.priority;
        }
      }
      if (querierIp == null) {
        final q = parseIgmpGeneralQuery(f);
        if (q != null) {
          querierIp = q.ip;
          querierVersion = q.version;
        }
      }
    }
    return L2RoleSniffResult(
      stpRootMac: rootMac,
      stpRootPriority: rootPriority,
      igmpQuerierIp: querierIp,
      igmpQuerierVersion: querierVersion,
    );
  }

  /// Extracts Root Bridge ID from an 802.1D/802.1w BPDU Ethernet frame.
  ///
  /// Layout: 14B Ethernet (802.3) + 3B LLC, then BPDU: protocol(2) version(1)
  /// type(1) flags(1) rootId(8: priority(2)+MAC(6)) ... (frame offset 22..29).
  static ({String mac, int priority})? parseBpdu(Uint8List f) {
    if (f.length < 30) return null;
    const dst = [0x01, 0x80, 0xC2, 0x00, 0x00, 0x00];
    for (var i = 0; i < 6; i++) {
      if (f[i] != dst[i]) return null;
    }
    // LLC DSAP/SSAP 0x42 and BPDU protocol id 0x0000.
    if (f[14] != 0x42 || f[15] != 0x42) return null;
    if (f[17] != 0 || f[18] != 0) return null;
    final type = f[20];
    if (type != 0x00 && type != 0x02 && type != 0x80) return null;
    if (type == 0x80) return null; // TCN BPDU carries no root id
    final priority = (f[22] << 8) | f[23];
    final mac = f
        .sublist(24, 30)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
    return (mac: mac, priority: priority);
  }

  /// Extracts the querier from an IPv4 IGMP General Query to 224.0.0.1.
  static ({String ip, String version})? parseIgmpGeneralQuery(Uint8List f) {
    var o = 12;
    if (f.length < 14) return null;
    if (f[o] == 0x81 && f[o + 1] == 0x00) o += 4; // 802.1Q tag
    if (f.length < o + 2 || f[o] != 0x08 || f[o + 1] != 0x00) return null;
    final ip = o + 2;
    if (f.length < ip + 20) return null;
    if (f[ip] >> 4 != 4) return null;
    final ihl = (f[ip] & 0x0F) * 4;
    if (ihl < 20 || f[ip + 9] != 2) return null;
    if (f[ip + 16] != 224 ||
        f[ip + 17] != 0 ||
        f[ip + 18] != 0 ||
        f[ip + 19] != 1) {
      return null;
    }
    final igmp = ip + ihl;
    if (f.length <= igmp || f[igmp] != 0x11) return null;
    final totalLen = (f[ip + 2] << 8) | f[ip + 3];
    final igmpLen = totalLen - ihl;
    final String version;
    if (igmpLen >= 12) {
      version = 'IGMPv3';
    } else if (igmpLen == 8) {
      version = 'IGMPv2';
    } else {
      return null;
    }
    final src = '${f[ip + 12]}.${f[ip + 13]}.${f[ip + 14]}.${f[ip + 15]}';
    return (ip: src, version: version);
  }
}
