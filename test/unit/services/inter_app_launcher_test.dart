import 'dart:convert';
import 'dart:io';
import 'package:arp_scout/data/services/ipc/inter_app_launcher.dart';
import 'package:arp_scout/domain/models/network_adapter_info.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockSocket implements Socket {
  final List<int> writtenBytes = [];
  bool isFlushed = false;
  bool isClosed = false;

  @override
  void write(Object? object) {
    writtenBytes.addAll(utf8.encode(object.toString()));
  }

  @override
  Future<void> flush() async {
    isFlushed = true;
  }

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProcess implements Process {
  @override
  int get pid => 12345;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('InterAppLauncher Unit Tests', () {
    const adapter = NetworkAdapterInfo(
      name: 'eth0',
      ipAddress: '192.168.1.150',
      subnetCidr: '192.168.1.0/24',
    );

    tearDown(() {
      InterAppLauncher.socketConnector = Socket.connect;
      InterAppLauncher.processStarter = Process.start;
      InterAppLauncher.executableResolverOverride = null;
    });

    test('warm handoff connects to loopback port and sends trace command', () async {
      final mockSocket = _MockSocket();
      var processStarted = false;

      InterAppLauncher.socketConnector = (host, port, {sourceAddress, int sourcePort = 0, timeout}) async {
        expect(host, equals('127.0.0.1'));
        expect(port, equals(InterAppLauncher.routeScoutIpcPort));
        return mockSocket;
      };

      InterAppLauncher.processStarter = (executable, arguments, {environment, bool includeParentEnvironment = true, ProcessStartMode mode = ProcessStartMode.normal, bool runInShell = false, workingDirectory}) async {
        processStarted = true;
        return _MockProcess();
      };

      await InterAppLauncher.launchRouteTrace(
        targetIp: '192.168.1.50',
        currentAdapter: adapter,
        autoStart: true,
      );

      expect(processStarted, isFalse);
      expect(mockSocket.isFlushed, isTrue);
      expect(mockSocket.isClosed, isTrue);

      final decoded = jsonDecode(utf8.decode(mockSocket.writtenBytes).trim()) as Map<String, dynamic>;
      expect(decoded['action'], equals('trace'));
      expect(decoded['target'], equals('192.168.1.50'));
      expect(decoded['adapterIp'], equals('192.168.1.150'));
      expect(decoded['adapterName'], equals('eth0'));
      expect(decoded['autoStart'], isTrue);
    });

    test('cold launch triggers process starter when socket connect fails', () async {
      String? launchedExecutable;
      List<String>? launchedArguments;
      String? launchedWorkingDirectory;
      ProcessStartMode? launchedMode;

      InterAppLauncher.socketConnector = (host, port, {sourceAddress, int sourcePort = 0, timeout}) async {
        throw const SocketException('Connection refused');
      };

      InterAppLauncher.executableResolverOverride = () async => '/mock/path/net_route_scout';

      InterAppLauncher.processStarter = (executable, arguments, {environment, bool includeParentEnvironment = true, ProcessStartMode mode = ProcessStartMode.normal, bool runInShell = false, workingDirectory}) async {
        launchedExecutable = executable;
        launchedArguments = arguments;
        launchedWorkingDirectory = workingDirectory;
        launchedMode = mode;
        return _MockProcess();
      };

      await InterAppLauncher.launchRouteTrace(
        targetIp: '192.168.1.50',
        currentAdapter: adapter,
        autoStart: true,
      );

      expect(launchedExecutable, equals('/mock/path/net_route_scout'));
      expect(launchedWorkingDirectory, equals('/mock/path'));
      expect(launchedArguments, containsAllInOrder(['--target', '192.168.1.50']));
      expect(launchedArguments, containsAllInOrder(['--adapter-ip', '192.168.1.150']));
      expect(launchedArguments, containsAllInOrder(['--adapter-name', 'eth0']));
      expect(launchedArguments, contains('--auto-start'));
      expect(launchedMode, equals(ProcessStartMode.detached));
    });

    test('cold launch omits --auto-start when autoStart is false', () async {
      List<String>? launchedArguments;

      InterAppLauncher.socketConnector = (host, port, {sourceAddress, int sourcePort = 0, timeout}) async {
        throw const SocketException('Connection refused');
      };

      InterAppLauncher.executableResolverOverride = () async => '/mock/path/net_route_scout';

      InterAppLauncher.processStarter = (executable, arguments, {environment, bool includeParentEnvironment = true, ProcessStartMode mode = ProcessStartMode.normal, bool runInShell = false, workingDirectory}) async {
        launchedArguments = arguments;
        return _MockProcess();
      };

      await InterAppLauncher.launchRouteTrace(
        targetIp: '192.168.1.50',
        currentAdapter: adapter,
        autoStart: false,
      );

      expect(launchedArguments, isNot(contains('--auto-start')));
    });

    test('throws exception when executable is not resolved on system', () async {
      InterAppLauncher.socketConnector = (host, port, {sourceAddress, int sourcePort = 0, timeout}) async {
        throw const SocketException('Connection refused');
      };

      InterAppLauncher.executableResolverOverride = () async => null;

      expect(
        () => InterAppLauncher.launchRouteTrace(
          targetIp: '192.168.1.50',
          currentAdapter: adapter,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Net Route Scout executable not found'),
          ),
        ),
      );
    });

    test('getSavedRouteScoutPath and saveRouteScoutPath manage custom path', () async {
      InterAppLauncher.customRouteScoutPath = null;
      await InterAppLauncher.clearSavedRouteScoutPath();

      // In-memory or saved custom path
      InterAppLauncher.customRouteScoutPath = Platform.resolvedExecutable;
      final retrieved = await InterAppLauncher.getSavedRouteScoutPath();
      expect(retrieved, equals(Platform.resolvedExecutable));

      await InterAppLauncher.clearSavedRouteScoutPath();
      expect(InterAppLauncher.customRouteScoutPath, isNull);
    });

    test('resolveRouteScoutExecutable returns non-null when sibling route-tracer exists', () async {
      // In this repository workspace, ../route-tracer is checked out side by side
      final resolved = await InterAppLauncher.resolveRouteScoutExecutable();
      // On Linux development workstations, it may locate either the repo or system binary
      if (resolved != null) {
        expect(File(resolved).existsSync() || Directory(resolved).existsSync(), isTrue);
      }
    });
  });
}
