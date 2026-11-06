import 'package:arp_scout/data/services/scanner/subnet_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubnetScannerService Unit Tests', () {
    test('expandTargetSubnet expands CIDR /24, /30, /31, /32', () {
      final ips30 = SubnetScannerService.expandTargetSubnet('10.0.0.0/30');
      // /30 has 4 IPs: .0 (net), .1, .2, .3 (bcast) -> usable: .1, .2
      expect(ips30, equals(['10.0.0.1', '10.0.0.2']));

      final ips31 = SubnetScannerService.expandTargetSubnet('10.0.0.0/31');
      // RFC 3021 /31 point-to-point: both .0 and .1 usable
      expect(ips31, equals(['10.0.0.0', '10.0.0.1']));

      final ips32 = SubnetScannerService.expandTargetSubnet('10.0.0.42/32');
      expect(ips32, equals(['10.0.0.42']));

      final ips24 = SubnetScannerService.expandTargetSubnet('192.168.1.0/24');
      expect(ips24.length, equals(254));
      expect(ips24.first, equals('192.168.1.1'));
      expect(ips24.last, equals('192.168.1.254'));
    });

    test('expandTargetSubnet handles range syntax with full IP and short octet', () {
      final rangeFull = SubnetScannerService.expandTargetSubnet('192.168.1.10-192.168.1.15');
      expect(rangeFull, equals([
        '192.168.1.10',
        '192.168.1.11',
        '192.168.1.12',
        '192.168.1.13',
        '192.168.1.14',
        '192.168.1.15',
      ]));

      final rangeShort = SubnetScannerService.expandTargetSubnet('192.168.1.50-53');
      expect(rangeShort, equals([
        '192.168.1.50',
        '192.168.1.51',
        '192.168.1.52',
        '192.168.1.53',
      ]));

      // Single IP
      final single = SubnetScannerService.expandTargetSubnet('192.168.1.100');
      expect(single, equals(['192.168.1.100']));

      // Inverted ranges or invalid values return empty
      expect(SubnetScannerService.expandTargetSubnet('192.168.1.50-40'), isEmpty);
      expect(SubnetScannerService.expandTargetSubnet('192.168.1.50-999'), isEmpty);
      expect(SubnetScannerService.expandTargetSubnet('not_an_ip'), isEmpty);
    });

    test('buildCliPreviewCommand sanitizes malicious shell characters', () {
      final safe = SubnetScannerService.buildCliPreviewCommand('192.168.1.0/24; cat /etc/passwd');
      expect(safe.contains('cat /etc/passwd'), isFalse);
      expect(safe.contains('192.168.1.0/24'), isTrue);

      final arpOnly = SubnetScannerService.buildCliPreviewCommand('192.168.1.0/24', arpOnly: true);
      expect(arpOnly, contains('arp'));
    });

    test('parseArpTableOutput handles complex Windows, Unix, and Linux formats', () {
      const sample = '''
Interface: 10.0.0.100 --- 0x5
  Internet Address      Physical Address      Type
  10.0.0.1              00-50-56-aa-bb-cc     dynamic
  10.0.0.2              00-50-56-aa-bb-cd     static
  224.0.0.22            01-00-5e-00-00-16     static
  10.0.0.255            ff-ff-ff-ff-ff-ff     static

? (192.168.1.1) at 0:11:22:33:44:55 on en0 ifscope [ethernet]
? (192.168.1.20) at (incomplete) on en0 ifscope [ethernet]

172.16.0.1 dev wlan0 lladdr 68:d7:9a:11:22:33 REACHABLE
172.16.0.2 dev wlan0  FAILED
''';

      final parsed = SubnetScannerService.parseArpTableOutput(sample);
      expect(parsed.length, equals(4));

      // Windows
      expect(parsed[0].ipAddress, equals('10.0.0.1'));
      expect(parsed[0].macAddress, equals('00:50:56:AA:BB:CC'));
      expect(parsed[0].interfaceIp, equals('10.0.0.100'));
      expect(parsed[1].ipAddress, equals('10.0.0.2'));

      // Unix / macOS
      expect(parsed[2].ipAddress, equals('192.168.1.1'));
      expect(parsed[2].macAddress, equals('00:11:22:33:44:55'));
      expect(parsed[2].interfaceIp, equals('en0'));

      // Linux
      expect(parsed[3].ipAddress, equals('172.16.0.1'));
      expect(parsed[3].macAddress, equals('68:D7:9A:11:22:33'));
      expect(parsed[3].interfaceIp, equals('wlan0'));
    });
  });
}
