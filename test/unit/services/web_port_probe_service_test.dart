import 'dart:io';

import 'package:arp_scout/data/services/scanner/web_port_probe_service.dart';
import 'package:arp_scout/domain/models/open_web_port.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpenWebPort', () {
    test('buildUrl omits default ports 80 and 443', () {
      const http80 = OpenWebPort(port: 80, isHttps: false);
      const https443 = OpenWebPort(port: 443, isHttps: true);

      expect(http80.scheme, 'http');
      expect(http80.buildUrl('10.201.100.50'), 'http://10.201.100.50');
      expect(http80.displayLabel, 'HTTP (80)');
      expect(http80.badgeText, '🌐 :80');

      expect(https443.scheme, 'https');
      expect(https443.buildUrl('10.201.100.50'), 'https://10.201.100.50');
      expect(https443.displayLabel, 'HTTPS (443)');
      expect(https443.badgeText, '🔒 :443');
    });

    test('buildUrl includes non-standard ports 8080-8085', () {
      const p8080 = OpenWebPort(port: 8080, isHttps: false);
      const p8085 = OpenWebPort(port: 8085, isHttps: false);

      expect(p8080.buildUrl('192.168.1.10'), 'http://192.168.1.10:8080');
      expect(p8085.buildUrl('192.168.1.10'), 'http://192.168.1.10:8085');
    });
  });

  group('WebPortProbeService', () {
    test('targetPorts covers 80, 443, and 8080-8085', () {
      expect(
        WebPortProbeService.targetPorts.map((p) => p.port).toList(),
        [80, 443, 8080, 8081, 8082, 8083, 8084, 8085],
      );
    });

    test('probeHost returns open ports in target order', () async {
      final service = WebPortProbeService(
        connector: (ip, port, timeout) async {
          expect(ip, '10.0.0.5');
          expect(timeout, const Duration(milliseconds: 300));
          return port == 443 || port == 8080 || port == 8083;
        },
      );

      final open = await service.probeHost('10.0.0.5');
      expect(
        open,
        const [
          OpenWebPort(port: 443, isHttps: true),
          OpenWebPort(port: 8080, isHttps: false),
          OpenWebPort(port: 8083, isHttps: false),
        ],
      );
    });

    test('probeHosts throttles concurrent probes via semaphore', () async {
      var active = 0;
      var maxObserved = 0;

      final service = WebPortProbeService(
        maxConcurrency: 32,
        connector: (ip, port, timeout) async {
          active++;
          if (active > maxObserved) maxObserved = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          return port == 80 && ip.endsWith('.1');
        },
      );

      final ips = List.generate(10, (i) => '192.168.1.${i + 1}');
      final results = await service.probeHosts(ips);

      expect(maxObserved, lessThanOrEqualTo(32));
      expect(maxObserved, greaterThan(1));
      expect(
        results['192.168.1.1'],
        const [OpenWebPort(port: 80, isHttps: false)],
      );
      expect(results['192.168.1.2'], isEmpty);
    });

    test('openUrlInBrowser rejects non-http schemes and launches http/https',
        () async {
      var called = false;
      String? launchedUrl;

      final invalid = await WebPortProbeService.openUrlInBrowser(
        'file:///etc/passwd',
        processStarter: (exe, args, {mode = ProcessStartMode.normal}) async {
          called = true;
          throw UnimplementedError();
        },
      );
      expect(invalid, isFalse);
      expect(called, isFalse);

      final valid = await WebPortProbeService.openUrlInBrowser(
        'http://10.201.100.50:8080',
        processStarter: (exe, args, {mode = ProcessStartMode.normal}) async {
          called = true;
          launchedUrl = args.last;
          return Process.start('true', const []);
        },
      );
      expect(valid, isTrue);
      expect(called, isTrue);
      expect(launchedUrl, 'http://10.201.100.50:8080');
    });
  });
}
