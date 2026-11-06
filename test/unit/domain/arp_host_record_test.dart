import 'dart:convert';
import 'package:arp_scout/domain/models/arp_host_record.dart';
import 'package:arp_scout/domain/models/host_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArpHostRecord Domain Model', () {
    test('displayName returns customName if set, otherwise hostname, otherwise -', () {
      const withCustom = ArpHostRecord(
        ipAddress: '192.168.1.10',
        ipNumeric: 10,
        macAddress: '00:11:22:33:44:55',
        vendor: 'Apple',
        hostname: 'macbook.local',
        customName: "Tom's Work Laptop",
        subnet: '192.168.1.0/24',
        interfaceName: 'en0',
        status: HostStatus.online,
        discoveryMethod: 'ARP',
        firstSeenMs: 0,
        lastSeenMs: 0,
      );
      expect(withCustom.displayName, equals("Tom's Work Laptop"));

      const withHostnameOnly = ArpHostRecord(
        ipAddress: '192.168.1.11',
        ipNumeric: 11,
        macAddress: '00:11:22:33:44:56',
        vendor: 'Apple',
        hostname: 'imac.local',
        customName: null,
        subnet: '192.168.1.0/24',
        interfaceName: 'en0',
        status: HostStatus.online,
        discoveryMethod: 'ARP',
        firstSeenMs: 0,
        lastSeenMs: 0,
      );
      expect(withHostnameOnly.displayName, equals('imac.local'));

      const withNeither = ArpHostRecord(
        ipAddress: '192.168.1.12',
        ipNumeric: 12,
        macAddress: '00:11:22:33:44:57',
        vendor: 'Unknown',
        hostname: '',
        customName: '   ',
        subnet: '192.168.1.0/24',
        interfaceName: 'en0',
        status: HostStatus.online,
        discoveryMethod: 'ARP',
        firstSeenMs: 0,
        lastSeenMs: 0,
      );
      expect(withNeither.displayName, equals('-'));
    });

    test('osHintFromTtl correctly identifies OS family based on ICMP TTL values', () {
      ArpHostRecord recordWithTtl(int? ttl) => ArpHostRecord(
            ipAddress: '192.168.1.1',
            ipNumeric: 1,
            macAddress: '00:11:22:33:44:55',
            vendor: 'Test',
            subnet: '192.168.1.0/24',
            interfaceName: 'en0',
            status: HostStatus.online,
            discoveryMethod: 'ARP',
            ttl: ttl,
            firstSeenMs: 0,
            lastSeenMs: 0,
          );

      expect(recordWithTtl(null).osHintFromTtl, equals('-'));
      expect(recordWithTtl(64).osHintFromTtl, equals('Linux / macOS / IoT (TTL 64)'));
      expect(recordWithTtl(48).osHintFromTtl, equals('Linux / macOS / IoT (TTL 48)'));
      expect(recordWithTtl(128).osHintFromTtl, equals('Windows (TTL 128)'));
      expect(recordWithTtl(100).osHintFromTtl, equals('Windows (TTL 100)'));
      expect(recordWithTtl(255).osHintFromTtl, equals('Network Gear / Cisco / Solaris (TTL 255)'));
    });

    test('hasConflict returns true for HostStatus.conflict or multiple conflicting MACs', () {
      const conflictStatus = ArpHostRecord(
        ipAddress: '192.168.1.50',
        ipNumeric: 50,
        macAddress: '00:11:22:33:44:55',
        vendor: 'Vendor A',
        subnet: '192.168.1.0/24',
        interfaceName: 'en0',
        status: HostStatus.conflict,
        discoveryMethod: 'ARP',
        firstSeenMs: 0,
        lastSeenMs: 0,
      );
      expect(conflictStatus.hasConflict, isTrue);

      const multipleMacs = ArpHostRecord(
        ipAddress: '192.168.1.51',
        ipNumeric: 51,
        macAddress: '00:11:22:33:44:55',
        vendor: 'Vendor A',
        subnet: '192.168.1.0/24',
        interfaceName: 'en0',
        status: HostStatus.online,
        discoveryMethod: 'ARP',
        conflictingMacs: ['00:11:22:33:44:55', 'AA:BB:CC:DD:EE:FF'],
        firstSeenMs: 0,
        lastSeenMs: 0,
      );
      expect(multipleMacs.hasConflict, isTrue);

      const noConflict = ArpHostRecord(
        ipAddress: '192.168.1.52',
        ipNumeric: 52,
        macAddress: '00:11:22:33:44:55',
        vendor: 'Vendor A',
        subnet: '192.168.1.0/24',
        interfaceName: 'en0',
        status: HostStatus.online,
        discoveryMethod: 'ARP',
        conflictingMacs: ['00:11:22:33:44:55'],
        firstSeenMs: 0,
        lastSeenMs: 0,
      );
      expect(noConflict.hasConflict, isFalse);
    });

    test('normalizeMac handles various formats, dashes, dots, and lowercase', () {
      expect(ArpHostRecord.normalizeMac('00-11-22-33-44-55'), equals('00:11:22:33:44:55'));
      expect(ArpHostRecord.normalizeMac('001122334455'), equals('00:11:22:33:44:55'));
      expect(ArpHostRecord.normalizeMac('0011.2233.4455'), equals('00:11:22:33:44:55'));
      expect(ArpHostRecord.normalizeMac('aa:bb:cc:dd:ee:ff'), equals('AA:BB:CC:DD:EE:FF'));
      expect(ArpHostRecord.normalizeMac('INVALID'), equals('INVALID'));
    });

    test('ipv4ToInt and intToIpv4 perform bidirectional 32-bit conversion accurately', () {
      const testIps = ['0.0.0.0', '127.0.0.1', '192.168.1.1', '10.0.0.254', '255.255.255.255'];
      for (final ip in testIps) {
        final num = ArpHostRecord.ipv4ToInt(ip);
        final back = ArpHostRecord.intToIpv4(num);
        expect(back, equals(ip));
      }
      expect(ArpHostRecord.ipv4ToInt('invalid.ip'), equals(0));
      expect(ArpHostRecord.ipv4ToInt('192.168.1'), equals(0));
      expect(ArpHostRecord.ipv4ToInt('192.168.1.999'), equals(0));
    });

    test('toSyntheticArpFrameBytes generates standard 42-byte Ethernet II + ARP reply frame', () {
      const record = ArpHostRecord(
        ipAddress: '192.168.1.50',
        ipNumeric: 50,
        macAddress: '00:11:22:33:44:55',
        vendor: 'Test',
        subnet: '192.168.1.0/24',
        interfaceName: 'en0',
        status: HostStatus.online,
        discoveryMethod: 'ARP',
        firstSeenMs: 0,
        lastSeenMs: 0,
      );

      final frame = record.toSyntheticArpFrameBytes(
        targetIp: '192.168.1.1',
        targetMac: 'AA:BB:CC:DD:EE:FF',
      );

      expect(frame.length, equals(42));
      // Ethernet Destination MAC (bytes 0-5)
      expect(frame.sublist(0, 6), equals([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]));
      // Ethernet Source MAC (bytes 6-11)
      expect(frame.sublist(6, 12), equals([0x00, 0x11, 0x22, 0x33, 0x44, 0x55]));
      // EtherType: ARP 0x0806 (bytes 12-13)
      expect(frame[12], equals(0x08));
      expect(frame[13], equals(0x06));
      // Hardware Type: Ethernet 1 (bytes 14-15)
      expect(frame[14], equals(0x00));
      expect(frame[15], equals(0x01));
      // Protocol Type: IPv4 0x0800 (bytes 16-17)
      expect(frame[16], equals(0x08));
      expect(frame[17], equals(0x00));
      // Hardware Size 6, Protocol Size 4 (bytes 18-19)
      expect(frame[18], equals(0x06));
      expect(frame[19], equals(0x04));
      // Opcode: ARP Reply 2 (bytes 20-21)
      expect(frame[20], equals(0x00));
      expect(frame[21], equals(0x02));
      // Sender MAC (bytes 22-27)
      expect(frame.sublist(22, 28), equals([0x00, 0x11, 0x22, 0x33, 0x44, 0x55]));
      // Sender IP (bytes 28-31) = 192.168.1.50
      expect(frame.sublist(28, 32), equals([192, 168, 1, 50]));
      // Target MAC (bytes 32-37)
      expect(frame.sublist(32, 38), equals([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]));
      // Target IP (bytes 38-41) = 192.168.1.1
      expect(frame.sublist(38, 42), equals([192, 168, 1, 1]));
    });

    test('toJson and fromRow serialize and deserialize database rows correctly', () {
      final row = {
        'id': 42,
        'ip_address': '10.0.0.1',
        'ip_numeric': 167772161,
        'mac_address': '00:0C:29:11:22:33',
        'vendor': 'VMware, Inc.',
        'hostname': 'router.corp',
        'custom_name': 'Edge Gateway',
        'subnet': '10.0.0.0/24',
        'interface_name': 'eth0',
        'status': HostStatus.online.code,
        'discovery_method': 'ARP + ICMP',
        'arp_type': 'dynamic',
        'rtt_ms': 1.25,
        'ttl': 64,
        'first_seen_ms': 1000000,
        'last_seen_ms': 2000000,
        'response_count': 5,
        'conflicting_macs': jsonEncode(['00:0C:29:11:22:33']),
        'associated_ips': jsonEncode(['10.0.0.1', '10.0.0.2']),
        'notes': 'Production gateway',
        'raw_arp_line': '10.0.0.1 lladdr 00:0c:29:11:22:33 REACHABLE',
      };

      final host = ArpHostRecord.fromRow(row);
      expect(host.id, equals(42));
      expect(host.ipAddress, equals('10.0.0.1'));
      expect(host.customName, equals('Edge Gateway'));
      expect(host.associatedIps, equals(['10.0.0.1', '10.0.0.2']));
      expect(host.rttMs, equals(1.25));
      expect(host.ttl, equals(64));

      final json = host.toJson();
      expect(json['id'], equals(42));
      expect(json['ipAddress'], equals('10.0.0.1'));
      expect(json['customName'], equals('Edge Gateway'));
      expect(json['status'], equals(HostStatus.online.label));
    });
  });
}
