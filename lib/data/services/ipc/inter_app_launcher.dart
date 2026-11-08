import 'dart:convert';
import 'dart:io';
import '../../../domain/models/network_adapter_info.dart';

typedef SocketConnector = Future<Socket> Function(
  dynamic host,
  int port, {
  dynamic sourceAddress,
  int sourcePort,
  Duration? timeout,
});

typedef ProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
  ProcessStartMode mode,
});

/// Launches or commands the Net Route Scout companion application (`net_route_scout`).
class InterAppLauncher {
  /// Well-known loopback IPC port for Net Route Scout.
  static const int routeScoutIpcPort = 44101;

  /// Visible for testing: socket connector override.
  static SocketConnector socketConnector = Socket.connect;

  /// Visible for testing: process starter override.
  static ProcessStarter processStarter = Process.start;

  /// Visible for testing: custom executable path resolver override.
  static Future<String?> Function()? executableResolverOverride;

  /// Commands Net Route Scout to trace [targetIp] using [currentAdapter].
  ///
  /// First attempts a warm handoff via loopback socket on port `44101`.
  /// If Net Route Scout is not running, performs a cold process launch with CLI flags.
  static Future<void> launchRouteTrace({
    required String targetIp,
    required NetworkAdapterInfo currentAdapter,
    bool autoStart = true,
  }) async {
    // 1. Check if Net Route Scout is already running via loopback socket
    try {
      final socket = await socketConnector(
        '127.0.0.1',
        routeScoutIpcPort,
        timeout: const Duration(milliseconds: 300),
      );
      final payload = jsonEncode({
        'action': 'trace',
        'target': targetIp,
        'adapterIp': currentAdapter.ipAddress,
        'adapterName': currentAdapter.name,
        'autoStart': autoStart,
      });
      socket.write('$payload\n');
      await socket.flush();
      await socket.close();
      return; // Successfully handed off to running instance!
    } catch (_) {
      // Net Route Scout is not running; perform cold process launch
    }

    // 2. Cold process launch with CLI arguments
    final exePath = await (executableResolverOverride != null
        ? executableResolverOverride!()
        : resolveRouteScoutExecutable());

    if (exePath == null) {
      throw Exception('Net Route Scout executable not found on system.');
    }

    final args = [
      '--target',
      targetIp,
      '--adapter-ip',
      currentAdapter.ipAddress,
      '--adapter-name',
      currentAdapter.name,
      if (autoStart) '--auto-start',
    ];

    await processStarter(exePath, args, mode: ProcessStartMode.detached);
  }

  /// Locates the Net Route Scout binary on the host system.
  static Future<String?> resolveRouteScoutExecutable() async {
    final localAppData = Platform.environment['LOCALAPPDATA'];

    final candidatePaths = <String>[
      if (Platform.isLinux) ...[
        '../route-tracer/build/linux/x64/release/bundle/net_route_scout',
        '../route-tracer/build/linux/x64/debug/bundle/net_route_scout',
        '/usr/local/bin/net-route-scout',
        '/opt/NetworkSuite/net-route-scout',
      ],
      if (Platform.isWindows) ...[
        r'..\route-tracer\build\windows\x64\runner\Release\net_route_scout.exe',
        r'..\route-tracer\build\windows\x64\runner\Debug\net_route_scout.exe',
        if (localAppData != null && localAppData.isNotEmpty)
          '$localAppData\\NetworkSuite\\net-route-scout.exe',
      ],
      if (Platform.isMacOS) ...[
        '../route-tracer/build/macos/Build/Products/Release/Net Route Scout.app/Contents/MacOS/net_route_scout',
        '/Applications/Net Route Scout.app/Contents/MacOS/net_route_scout',
      ],
    ];

    for (final p in candidatePaths) {
      if (await File(p).exists()) return p;
    }

    // Fallback: check system $PATH
    final pathBinaries = ['net-route-scout', 'net_route_scout'];
    for (final bin in pathBinaries) {
      try {
        final whichCmd = Platform.isWindows ? 'where' : 'which';
        final res = await Process.run(whichCmd, [bin]);
        if (res.exitCode == 0) {
          final foundPath = res.stdout.toString().trim().split('\n').first.trim();
          if (foundPath.isNotEmpty && await File(foundPath).exists()) {
            return foundPath;
          }
        }
      } catch (_) {}
    }

    return null;
  }
}
