import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:arp_scout/data/services/ipc/inter_app_ipc_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InterAppIpcService Unit Tests', () {
    const testPort = 44199;

    tearDown(() async {
      await InterAppIpcService.stopListener();
    });

    test('listens on loopback port and decodes incoming JSON command', () async {
      final completer = Completer<Map<String, dynamic>>();

      final server = await InterAppIpcService.startListener(
        port: testPort,
        onCommand: (payload) {
          if (!completer.isCompleted) {
            completer.complete(payload);
          }
        },
      );

      expect(server, isNotNull);

      // Connect as companion app
      final socket = await Socket.connect(
        '127.0.0.1',
        testPort,
        timeout: const Duration(milliseconds: 500),
      );

      final payload = {
        'action': 'scan',
        'subnet': '10.20.30.0/24',
        'adapterIp': '10.20.30.5',
        'adapterName': 'eth1',
        'autoStart': true,
      };

      socket.write('${jsonEncode(payload)}\n');
      await socket.flush();
      await socket.close();

      final received = await completer.future.timeout(
        const Duration(seconds: 2),
      );

      expect(received['action'], equals('scan'));
      expect(received['subnet'], equals('10.20.30.0/24'));
      expect(received['adapterIp'], equals('10.20.30.5'));
      expect(received['adapterName'], equals('eth1'));
      expect(received['autoStart'], isTrue);
    });

    test('ignores non-JSON or malformed payload gracefully', () async {
      var commandInvoked = false;

      await InterAppIpcService.startListener(
        port: testPort,
        onCommand: (_) {
          commandInvoked = true;
        },
      );

      final socket = await Socket.connect('127.0.0.1', testPort);
      socket.write('THIS_IS_NOT_JSON\n\n');
      await socket.flush();
      await socket.close();

      await Future.delayed(const Duration(milliseconds: 100));
      expect(commandInvoked, isFalse);
    });
  });
}
