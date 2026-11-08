import 'dart:convert';
import 'dart:io';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:path/path.dart' as p;
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

  /// Optional in-memory override for Net Route Scout executable path.
  static String? customRouteScoutPath;

  /// Config file name storing user-specified or discovered application paths.
  static const String configFileName = 'inter_app_config.json';

  /// Resolves the config file location in the canonical NetworkSuite directory.
  static File getConfigFile() {
    final dir = SharedDeviceDatabase.getDefaultDirectoryPath();
    return File(p.join(dir, configFileName));
  }

  /// Checks if [path] points to an existing file, or an existing .app bundle on macOS.
  static bool _isValidExecutableOrApp(String path) {
    if (path.isEmpty) return false;
    final file = File(path);
    if (file.existsSync()) return true;
    if (Platform.isMacOS && (path.endsWith('.app') || path.endsWith('.app/')) && Directory(path).existsSync()) {
      return true;
    }
    return false;
  }

  /// If [path] is a macOS .app bundle directory, resolves the internal binary in Contents/MacOS.
  static String _normalizeExecutablePath(String path) {
    if (Platform.isMacOS && (path.endsWith('.app') || path.endsWith('.app/'))) {
      final macOsDir = Directory(p.join(path, 'Contents', 'MacOS'));
      if (macOsDir.existsSync()) {
        const candidateNames = [
          'net_route_scout',
          'net-route-scout',
          'Net Route Scout',
          'Net-Route-Scout',
          'route-tracer',
          'Route Tracer',
        ];
        for (final name in candidateNames) {
          final candidate = File(p.join(macOsDir.path, name));
          if (candidate.existsSync()) return candidate.path;
        }
        // Fallback: pick the first regular file in Contents/MacOS
        final entities = macOsDir.listSync();
        for (final entity in entities) {
          if (entity is File) return entity.path;
        }
      }
    }
    return path;
  }

  /// Retrieves previously saved Net Route Scout path if it exists on disk.
  static Future<String?> getSavedRouteScoutPath() async {
    if (customRouteScoutPath != null && _isValidExecutableOrApp(customRouteScoutPath!)) {
      return _normalizeExecutablePath(customRouteScoutPath!);
    }

    try {
      final file = getConfigFile();
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      final json = jsonDecode(content);
      if (json is Map<String, dynamic> && json['routeScoutPath'] is String) {
        final savedPath = json['routeScoutPath'] as String;
        if (_isValidExecutableOrApp(savedPath)) {
          return _normalizeExecutablePath(savedPath);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Persists a custom or detected Net Route Scout path into the NetworkSuite shared config.
  static Future<void> saveRouteScoutPath(String path) async {
    final normalized = _normalizeExecutablePath(path);
    customRouteScoutPath = normalized;
    try {
      final file = getConfigFile();
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      Map<String, dynamic> config = {};
      if (await file.exists()) {
        try {
          final existing = jsonDecode(await file.readAsString());
          if (existing is Map<String, dynamic>) config = existing;
        } catch (_) {}
      }
      config['routeScoutPath'] = normalized;
      await file.writeAsString(jsonEncode(config));
    } catch (_) {}
  }

  /// Clears any saved or in-memory route scout path.
  static Future<void> clearSavedRouteScoutPath() async {
    customRouteScoutPath = null;
    try {
      final file = getConfigFile();
      if (await file.exists()) {
        final existing = jsonDecode(await file.readAsString());
        if (existing is Map<String, dynamic>) {
          existing.remove('routeScoutPath');
          await file.writeAsString(jsonEncode(existing));
        }
      }
    } catch (_) {}
  }

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

    // Cache valid discovered path for future instant launches
    await saveRouteScoutPath(exePath);

    final args = [
      '--target',
      targetIp,
      '--adapter-ip',
      currentAdapter.ipAddress,
      '--adapter-name',
      currentAdapter.name,
      if (autoStart) '--auto-start',
    ];

    // Ensure Linux/macOS executable bit is set if the user extracted an archive
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['+x', exePath]);
      } catch (_) {}
    }

    // Pass workingDirectory as the executable's folder so dynamic libraries
    // (flutter_windows.dll / libflutter.so / Frameworks) and data/ assets load cleanly.
    final workingDir = File(exePath).parent.path;
    await processStarter(
      exePath,
      args,
      workingDirectory: workingDir,
      mode: ProcessStartMode.detached,
    );
  }

  /// Locates the Net Route Scout binary on the host system.
  static Future<String?> resolveRouteScoutExecutable() async {
    // 1. Check saved custom path
    final savedPath = await getSavedRouteScoutPath();
    if (savedPath != null && _isValidExecutableOrApp(savedPath)) {
      return _normalizeExecutablePath(savedPath);
    }

    // 2. Platform-specific candidate checks
    final candidates = <String>[];

    if (Platform.isWindows) {
      _addWindowsCandidates(candidates);
    } else if (Platform.isLinux) {
      _addLinuxCandidates(candidates);
    } else if (Platform.isMacOS) {
      _addMacCandidates(candidates);
    }

    for (final p in candidates) {
      if (p.isNotEmpty && _isValidExecutableOrApp(p)) {
        return _normalizeExecutablePath(p);
      }
    }

    // 3. Platform-specific index/registry checks
    if (Platform.isWindows) {
      final regPath = await _findInWindowsRegistry();
      if (regPath != null) return _normalizeExecutablePath(regPath);
    } else if (Platform.isMacOS) {
      final spotPath = await _findWithMacSpotlight();
      if (spotPath != null) return _normalizeExecutablePath(spotPath);
    }

    // 4. Fallback: check system $PATH via where / which
    final pathBin = await _findInSystemPath();
    if (pathBin != null) return _normalizeExecutablePath(pathBin);

    return null;
  }

  static void _addWindowsCandidates(List<String> candidates) {
    const exeNames = [
      'net_route_scout.exe',
      'net-route-scout.exe',
      'Net Route Scout.exe',
    ];

    const folderNames = [
      'route-tracer',
      'Net-Route-Scout',
      'Net Route Scout',
      'net-route-scout',
      'net_route_scout',
      'NetRouteScout',
      'route-tracer_windows_x64',
      'Net-Route-Scout_windows_x64',
      'Net Route Scout_windows_x64',
    ];

    // A. Relative to the running ARP Scout executable
    try {
      final currentExe = File(Platform.resolvedExecutable);
      final exeDir = currentExe.parent;
      final parentDir = exeDir.parent;

      // In the same directory
      for (final exe in exeNames) {
        candidates.add(p.join(exeDir.path, exe));
      }

      // In sibling directories
      for (final folder in folderNames) {
        for (final exe in exeNames) {
          candidates.add(p.join(parentDir.path, folder, exe));
          candidates.add(
            p.join(parentDir.path, folder, 'build', 'windows', 'x64', 'runner', 'Release', exe),
          );
          candidates.add(
            p.join(parentDir.path, folder, 'build', 'windows', 'x64', 'runner', 'Debug', exe),
          );
        }
      }
    } catch (_) {}

    // B. Relative to Directory.current (e.g. workspace root during development)
    try {
      final currentDir = Directory.current;
      final parentDir = currentDir.parent;

      for (final folder in folderNames) {
        for (final exe in exeNames) {
          candidates.add(p.join(parentDir.path, folder, exe));
          candidates.add(
            p.join(parentDir.path, folder, 'build', 'windows', 'x64', 'runner', 'Release', exe),
          );
          candidates.add(
            p.join(parentDir.path, folder, 'build', 'windows', 'x64', 'runner', 'Debug', exe),
          );
          candidates.add(p.join(currentDir.path, folder, exe));
        }
      }
    } catch (_) {}

    // C. Standard Windows environment base paths
    final env = Platform.environment;
    final baseDirs = <String>[
      if (env['LOCALAPPDATA'] != null && env['LOCALAPPDATA']!.isNotEmpty) env['LOCALAPPDATA']!,
      if (env['PROGRAMFILES'] != null && env['PROGRAMFILES']!.isNotEmpty) env['PROGRAMFILES']!,
      if (env['ProgramFiles(x86)'] != null && env['ProgramFiles(x86)']!.isNotEmpty)
        env['ProgramFiles(x86)']!,
      if (env['ProgramW6432'] != null && env['ProgramW6432']!.isNotEmpty) env['ProgramW6432']!,
      if (env['PROGRAMDATA'] != null && env['PROGRAMDATA']!.isNotEmpty) env['PROGRAMDATA']!,
      if (env['APPDATA'] != null && env['APPDATA']!.isNotEmpty) env['APPDATA']!,
      if (env['USERPROFILE'] != null && env['USERPROFILE']!.isNotEmpty) ...[
        env['USERPROFILE']!,
        p.join(env['USERPROFILE']!, 'Downloads'),
        p.join(env['USERPROFILE']!, 'Desktop'),
        p.join(env['USERPROFILE']!, 'Tools'),
        p.join(env['USERPROFILE']!, 'Apps'),
      ],
      r'C:\Program Files',
      r'C:\Program Files (x86)',
      r'C:\NetworkSuite',
      r'C:\Tools',
    ];

    const subDirs = [
      'NetworkSuite',
      r'NetworkSuite\Net Route Scout',
      r'NetworkSuite\Net-Route-Scout',
      r'NetworkSuite\route-tracer',
      r'Programs\NetworkSuite',
      r'Programs\Net Route Scout',
      r'Programs\Net-Route-Scout',
      r'Programs\route-tracer',
      'Net Route Scout',
      'Net-Route-Scout',
      'route-tracer',
      'route-tracer_windows_x64',
      'Net-Route-Scout_windows_x64',
    ];

    for (final base in baseDirs) {
      for (final exe in exeNames) {
        candidates.add(p.join(base, exe));
        for (final sub in subDirs) {
          candidates.add(p.join(base, sub, exe));
        }
      }
    }
  }

  static void _addLinuxCandidates(List<String> candidates) {
    const binNames = [
      'net_route_scout',
      'net-route-scout',
      'Net Route Scout',
      'Net-Route-Scout',
      'NetRouteScout',
    ];

    const folderNames = [
      'route-tracer',
      'route-tracer_linux_x64',
      'Net-Route-Scout',
      'Net Route Scout',
      'net-route-scout',
      'net_route_scout',
      'NetRouteScout',
    ];

    // A. Relative to the running ARP Scout executable
    try {
      final currentExe = File(Platform.resolvedExecutable);
      final exeDir = currentExe.parent;
      final parentDir = exeDir.parent;

      // In the same directory (e.g. all suite binaries installed in /opt/NetworkSuite or bundle)
      for (final bin in binNames) {
        candidates.add(p.join(exeDir.path, bin));
      }

      // Sibling folders
      for (final folder in folderNames) {
        for (final bin in binNames) {
          candidates.add(p.join(parentDir.path, folder, bin));
          candidates.add(p.join(parentDir.path, folder, 'bundle', bin));
          candidates.add(p.join(parentDir.path, folder, 'build', 'linux', 'x64', 'release', 'bundle', bin));
          candidates.add(p.join(parentDir.path, folder, 'build', 'linux', 'x64', 'debug', 'bundle', bin));
        }
      }

      // Up to 5 parent levels for development checkouts
      var searchDir = currentExe.parent;
      for (var i = 0; i < 5; i++) {
        if (searchDir.path == searchDir.parent.path) break;
        searchDir = searchDir.parent;
        for (final folder in folderNames) {
          for (final bin in binNames) {
            candidates.add(p.join(searchDir.path, folder, bin));
            candidates.add(p.join(searchDir.path, folder, 'bundle', bin));
            candidates.add(p.join(searchDir.path, folder, 'build', 'linux', 'x64', 'release', 'bundle', bin));
            candidates.add(p.join(searchDir.path, folder, 'build', 'linux', 'x64', 'debug', 'bundle', bin));
          }
        }
      }
    } catch (_) {}

    // B. Relative to Directory.current (e.g. workspace root during development)
    try {
      final currentDir = Directory.current;
      final parentDir = currentDir.parent;

      for (final folder in folderNames) {
        for (final bin in binNames) {
          candidates.add(p.join(parentDir.path, folder, bin));
          candidates.add(p.join(parentDir.path, folder, 'bundle', bin));
          candidates.add(p.join(parentDir.path, folder, 'build', 'linux', 'x64', 'release', 'bundle', bin));
          candidates.add(p.join(parentDir.path, folder, 'build', 'linux', 'x64', 'debug', 'bundle', bin));
          candidates.add(p.join(currentDir.path, folder, bin));
          candidates.add(p.join(currentDir.path, folder, 'bundle', bin));
          candidates.add(p.join(currentDir.path, folder, 'build', 'linux', 'x64', 'release', 'bundle', bin));
        }
      }
    } catch (_) {}

    // C. Standard Linux system and user directories
    final home = Platform.environment['HOME'] ?? '';
    final baseDirs = <String>[
      '/usr/local/bin',
      '/usr/bin',
      '/opt/NetworkSuite',
      '/opt/NetworkSuite/bin',
      '/opt/NetworkSuite/net_route_scout',
      '/opt/NetworkSuite/Net Route Scout',
      '/opt/net_route_scout',
      '/opt/net-route-scout',
      '/opt/route-tracer',
      if (home.isNotEmpty) p.join(home, '.local', 'bin'),
      if (home.isNotEmpty) p.join(home, '.local', 'share', 'NetworkSuite'),
      if (home.isNotEmpty) p.join(home, 'bin'),
      if (home.isNotEmpty) p.join(home, 'Applications'),
      if (home.isNotEmpty) p.join(home, 'Applications', 'NetworkSuite'),
      if (home.isNotEmpty) p.join(home, 'Downloads'),
      if (home.isNotEmpty) p.join(home, 'Desktop'),
    ];

    for (final base in baseDirs) {
      for (final bin in binNames) {
        candidates.add(p.join(base, bin));
        for (final folder in folderNames) {
          candidates.add(p.join(base, folder, bin));
          candidates.add(p.join(base, folder, 'bundle', bin));
        }
      }
    }
  }

  static void _addMacCandidates(List<String> candidates) {
    const appNames = [
      'Net Route Scout.app',
      'net_route_scout.app',
      'Net-Route-Scout.app',
      'route-tracer.app',
      'Route Tracer.app',
    ];

    const folderNames = [
      'route-tracer',
      'route-tracer_macos',
      'Net-Route-Scout',
      'Net Route Scout',
      'net-route-scout',
      'net_route_scout',
      'NetRouteScout',
    ];

    // A. Relative to the running ARP Scout executable
    try {
      final currentExe = File(Platform.resolvedExecutable);
      // macOS bundle structure: AppName.app/Contents/MacOS/executable
      final macOsDir = currentExe.parent;
      final contentsDir = macOsDir.parent;
      final appDir = contentsDir.parent;
      final appsDir = appDir.parent; // /Applications or enclosing folder

      // Sibling .app bundles in the same parent directory (e.g. /Applications)
      for (final app in appNames) {
        candidates.add(p.join(appsDir.path, app));
        candidates.add(p.join(appsDir.path, 'NetworkSuite', app));
      }

      // Up to 6 levels up for development checkouts
      var searchDir = currentExe.parent;
      for (var i = 0; i < 6; i++) {
        if (searchDir.path == searchDir.parent.path) break;
        searchDir = searchDir.parent;
        for (final folder in folderNames) {
          for (final app in appNames) {
            candidates.add(p.join(searchDir.path, folder, app));
            candidates.add(p.join(searchDir.path, folder, 'build', 'macos', 'Build', 'Products', 'Release', app));
            candidates.add(p.join(searchDir.path, folder, 'build', 'macos', 'Build', 'Products', 'Debug', app));
          }
        }
      }
    } catch (_) {}

    // B. Relative to Directory.current (e.g. workspace root during development)
    try {
      final currentDir = Directory.current;
      final parentDir = currentDir.parent;

      for (final folder in folderNames) {
        for (final app in appNames) {
          candidates.add(p.join(parentDir.path, folder, app));
          candidates.add(p.join(parentDir.path, folder, 'build', 'macos', 'Build', 'Products', 'Release', app));
          candidates.add(p.join(parentDir.path, folder, 'build', 'macos', 'Build', 'Products', 'Debug', app));
          candidates.add(p.join(currentDir.path, folder, app));
          candidates.add(p.join(currentDir.path, folder, 'build', 'macos', 'Build', 'Products', 'Release', app));
        }
      }
    } catch (_) {}

    // C. Standard macOS applications and user folders
    final home = Platform.environment['HOME'] ?? '';
    final baseDirs = <String>[
      '/Applications',
      '/Applications/NetworkSuite',
      if (home.isNotEmpty) p.join(home, 'Applications'),
      if (home.isNotEmpty) p.join(home, 'Applications', 'NetworkSuite'),
      if (home.isNotEmpty) p.join(home, 'Downloads'),
      if (home.isNotEmpty) p.join(home, 'Desktop'),
    ];

    for (final base in baseDirs) {
      for (final app in appNames) {
        candidates.add(p.join(base, app));
        for (final folder in folderNames) {
          candidates.add(p.join(base, folder, app));
        }
      }
    }
  }

  /// Queries macOS Spotlight index (mdfind) for Net Route Scout.
  static Future<String?> _findWithMacSpotlight() async {
    if (!Platform.isMacOS) return null;

    final spotlightQueries = [
      'kMDItemCFBundleIdentifier == "io.github.tommcguire.netRouteScout"',
      'kMDItemCFBundleIdentifier == "io.github.tommcguire.net_route_scout"',
      'kMDItemFSName == "net_route_scout.app"',
      'kMDItemFSName == "Net Route Scout.app"',
      'kMDItemFSName == "Net-Route-Scout.app"',
      'kMDItemFSName == "route-tracer.app"',
    ];

    for (final query in spotlightQueries) {
      try {
        final res = await Process.run('mdfind', [query]);
        if (res.exitCode == 0) {
          final lines = res.stdout.toString().split(RegExp(r'\r?\n'));
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty && _isValidExecutableOrApp(trimmed)) {
              return _normalizeExecutablePath(trimmed);
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> _findInWindowsRegistry() async {
    const regKeys = [
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\net_route_scout.exe',
      r'HKLM\Software\Microsoft\Windows\CurrentVersion\App Paths\net_route_scout.exe',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\net-route-scout.exe',
      r'HKLM\Software\Microsoft\Windows\CurrentVersion\App Paths\net-route-scout.exe',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\Net Route Scout.exe',
      r'HKLM\Software\Microsoft\Windows\CurrentVersion\App Paths\Net Route Scout.exe',
    ];

    for (final key in regKeys) {
      try {
        final res = await Process.run('reg', ['query', key, '/ve']);
        if (res.exitCode == 0) {
          final out = res.stdout.toString();
          for (final line in out.split(RegExp(r'\r?\n'))) {
            if (line.contains('REG_SZ') || line.contains('REG_EXPAND_SZ')) {
              final parts = line.split(RegExp(r'REG_(?:EXPAND_)?SZ'));
              if (parts.length > 1) {
                final regPath = parts.last.trim().replaceAll('"', '');
                if (regPath.isNotEmpty && await File(regPath).exists()) {
                  return regPath;
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static Future<String?> _findInSystemPath() async {
    final whichCmd = Platform.isWindows ? 'where' : 'which';
    final pathBinaries = [
      if (Platform.isWindows) ...[
        'net_route_scout.exe',
        'net_route_scout',
        'net-route-scout.exe',
        'net-route-scout',
        'Net Route Scout.exe',
      ] else ...[
        'net_route_scout',
        'net-route-scout',
        'Net Route Scout',
        'Net-Route-Scout',
        'route-tracer',
      ],
    ];

    for (final bin in pathBinaries) {
      try {
        final res = await Process.run(whichCmd, [bin]);
        if (res.exitCode == 0) {
          final lines = res.stdout.toString().split(RegExp(r'\r?\n'));
          for (final line in lines) {
            final trimmed = line.trim().replaceAll('"', '');
            if (trimmed.isNotEmpty && await File(trimmed).exists()) {
              return trimmed;
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }
}
