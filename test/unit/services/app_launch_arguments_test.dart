import 'package:arp_scout/data/services/ipc/app_launch_arguments.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLaunchArguments CLI Parser', () {
    test('parses empty args to default values', () {
      final args = AppLaunchArguments.parse([]);
      expect(args.subnet, isNull);
      expect(args.adapterIp, isNull);
      expect(args.adapterName, isNull);
      expect(args.target, isNull);
      expect(args.autoStart, isFalse);
    });

    test('parses space-separated CLI arguments', () {
      final args = AppLaunchArguments.parse([
        '--subnet',
        '192.168.10.0/24',
        '--adapter-ip',
        '192.168.10.15',
        '--adapter-name',
        'Ethernet0',
        '--target',
        '192.168.10.1',
        '--auto-start',
      ]);

      expect(args.subnet, equals('192.168.10.0/24'));
      expect(args.adapterIp, equals('192.168.10.15'));
      expect(args.adapterName, equals('Ethernet0'));
      expect(args.target, equals('192.168.10.1'));
      expect(args.autoStart, isTrue);
    });

    test('parses equal-separated CLI arguments', () {
      final args = AppLaunchArguments.parse([
        '--subnet=10.0.0.0/16',
        '--adapter-ip=10.0.0.2',
        '--adapter-name=wlan0',
        '--target=10.0.0.254',
      ]);

      expect(args.subnet, equals('10.0.0.0/16'));
      expect(args.adapterIp, equals('10.0.0.2'));
      expect(args.adapterName, equals('wlan0'));
      expect(args.target, equals('10.0.0.254'));
      expect(args.autoStart, isFalse);
    });

    test('handles trailing flags missing values gracefully', () {
      final args = AppLaunchArguments.parse([
        '--subnet',
        '172.16.0.0/12',
        '--adapter-ip',
      ]);

      expect(args.subnet, equals('172.16.0.0/12'));
      expect(args.adapterIp, isNull);
      expect(args.autoStart, isFalse);
    });

    test('toString formats all fields cleanly', () {
      final args = AppLaunchArguments.parse([
        '--subnet',
        '192.168.1.0/24',
        '--auto-start',
      ]);
      expect(args.toString(), contains('192.168.1.0/24'));
      expect(args.toString(), contains('autoStart: true'));
    });
  });
}
