import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../../../domain/models/open_web_port.dart';

typedef TcpPortConnector = Future<bool> Function(
  String ip,
  int port,
  Duration timeout,
);

typedef BrowserProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  ProcessStartMode mode,
});

/// Fast, semaphore-throttled TCP probe for common HTTP/HTTPS management ports.
class WebPortProbeService {
  WebPortProbeService({
    this.timeout = const Duration(milliseconds: 300),
    this.maxConcurrency = 32,
    TcpPortConnector? connector,
  }) : _connector = connector ?? _defaultSocketConnector;

  static const List<OpenWebPort> targetPorts = [
    OpenWebPort(port: 80, isHttps: false),
    OpenWebPort(port: 443, isHttps: true),
    OpenWebPort(port: 8080, isHttps: false),
    OpenWebPort(port: 8081, isHttps: false),
    OpenWebPort(port: 8082, isHttps: false),
    OpenWebPort(port: 8083, isHttps: false),
    OpenWebPort(port: 8084, isHttps: false),
    OpenWebPort(port: 8085, isHttps: false),
  ];

  final Duration timeout;
  final int maxConcurrency;
  final TcpPortConnector _connector;

  static Future<bool> _defaultSocketConnector(
    String ip,
    int port,
    Duration timeout,
  ) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Probes all [targetPorts] for a single [ip] using a bounded semaphore.
  Future<List<OpenWebPort>> probeHost(String ip) async {
    final results = await probeHosts([ip]);
    return results[ip] ?? const [];
  }

  /// Probes all [targetPorts] across [ips], throttled to [maxConcurrency]
  /// simultaneous socket attempts.
  Future<Map<String, List<OpenWebPort>>> probeHosts(
    Iterable<String> ips,
  ) async {
    final uniqueIps = ips.where((ip) => ip.trim().isNotEmpty).toSet().toList();
    if (uniqueIps.isEmpty) return const {};

    final semaphore = _AsyncSemaphore(maxConcurrency);
    final openByIp = <String, List<OpenWebPort>>{
      for (final ip in uniqueIps) ip: <OpenWebPort>[],
    };

    final futures = <Future<void>>[];
    for (final ip in uniqueIps) {
      for (final candidate in targetPorts) {
        futures.add(() async {
          await semaphore.acquire();
          try {
            final isOpen = await _connector(ip, candidate.port, timeout);
            if (isOpen) {
              openByIp[ip]!.add(candidate);
            }
          } finally {
            semaphore.release();
          }
        }());
      }
    }

    await Future.wait(futures);

    final order = {
      for (var i = 0; i < targetPorts.length; i++) targetPorts[i].port: i,
    };
    for (final ports in openByIp.values) {
      ports.sort((a, b) => (order[a.port] ?? 0).compareTo(order[b.port] ?? 0));
    }
    return openByIp;
  }

  /// Opens an HTTP/HTTPS [url] in the OS default web browser.
  static Future<bool> openUrlInBrowser(
    String url, {
    BrowserProcessStarter? processStarter,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }

    final starter = processStarter ??
        (String exe, List<String> args,
            {ProcessStartMode mode = ProcessStartMode.normal}) {
          return Process.start(exe, args, mode: mode);
        };

    try {
      if (Platform.isLinux) {
        await starter('xdg-open', [uri.toString()],
            mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isMacOS) {
        await starter('open', [uri.toString()],
            mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isWindows) {
        await starter('cmd', ['/c', 'start', '', uri.toString()],
            mode: ProcessStartMode.detached);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

class _AsyncSemaphore {
  _AsyncSemaphore(this._maxCount) : assert(_maxCount > 0);

  final int _maxCount;
  int _activeCount = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<void> acquire() {
    if (_activeCount < _maxCount) {
      _activeCount++;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.addLast(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      next.complete();
    } else if (_activeCount > 0) {
      _activeCount--;
    }
  }
}
