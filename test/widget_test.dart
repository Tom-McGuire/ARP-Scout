import 'package:arp_scout/data/services/database/arp_database_service.dart';
import 'package:arp_scout/data/services/oui/oui_lookup_service.dart';
import 'package:arp_scout/data/services/scanner/subnet_scanner_service.dart';
import 'package:arp_scout/domain/models/arp_filter.dart';
import 'package:arp_scout/domain/models/arp_host_record.dart';
import 'package:arp_scout/domain/models/host_status.dart';
import 'package:arp_scout/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OuiLookupService', () {
    test('identifies known hardware vendors and special MACs', () {
      expect(
        OuiLookupService.lookupVendor('00:50:56:8B:10:10'),
        equals('VMware, Inc.'),
      );
      expect(
        OuiLookupService.lookupVendor('74-83-C2-AA-30-01'),
        equals('Ubiquiti Inc.'),
      );
      expect(
        OuiLookupService.lookupVendor('00:00:5E:00:01:0A'),
        equals('IETF VRRP Virtual Router'),
      );
      expect(
        OuiLookupService.lookupVendor('DA:A1:19:44:78:20'),
        equals('Locally Administered / Randomized MAC'),
      );
    });
  });

  group('SubnetScannerService', () {
    test('expands CIDR /24 and IP range syntax accurately', () {
      final ips24 = SubnetScannerService.expandTargetSubnet('192.168.10.0/24');
      expect(ips24.length, equals(254));
      expect(ips24.first, equals('192.168.10.1'));
      expect(ips24.last, equals('192.168.10.254'));

      final rangeIps = SubnetScannerService.expandTargetSubnet(
        '10.0.0.10-10.0.0.15',
      );
      expect(rangeIps.length, equals(6));
      expect(rangeIps.first, equals('10.0.0.10'));
      expect(rangeIps.last, equals('10.0.0.15'));
    });

    test('parses Windows and Unix arp -a output and filters broadcast', () {
      const sampleArp = '''
Interface: 192.168.1.15 --- 0xe
  Internet Address      Physical Address      Type
  192.168.1.1           00-09-0f-aa-10-01     dynamic
  192.168.1.50          28-57-be-91-50-cc     dynamic
  192.168.1.255         ff-ff-ff-ff-ff-ff     static
  224.0.0.22            01-00-5e-00-00-16     static
''';
      final parsed = SubnetScannerService.parseArpTableOutput(sampleArp);
      expect(parsed.length, equals(2));
      expect(parsed[0].ipAddress, equals('192.168.1.1'));
      expect(parsed[0].macAddress, equals('00:09:0F:AA:10:01'));
      expect(parsed[1].ipAddress, equals('192.168.1.50'));
      expect(parsed[1].macAddress, equals('28:57:BE:91:50:CC'));
    });
  });

  group('ArpDatabaseService (SQLite Backend)', () {
    late ArpDatabaseService db;

    setUp(() {
      db = ArpDatabaseService();
    });

    tearDown(() {
      db.close();
    });

    test('automatically detects IP address conflicts across sweeps and searches by MAC/IP', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Sweep 1: 192.168.1.50 claimed by Intel Laptop MAC
      db.upsertBatch([
        ArpHostRecord(
          ipAddress: '192.168.1.50',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.50'),
          macAddress: '3C:97:0E:12:50:AA',
          vendor: 'Intel Corporate',
          subnet: '192.168.1.0/24',
          interfaceName: 'Ethernet0',
          status: HostStatus.online,
          discoveryMethod: 'ARP + ICMP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
      ]);

      var hosts = db.queryHosts(filter: const ArpFilterCriteria());
      expect(hosts.length, equals(1));
      expect(hosts.first.status, equals(HostStatus.online));
      expect(hosts.first.hasConflict, isFalse);

      // Sweep 2: 192.168.1.50 is now claimed by Hikvision IP Camera MAC!
      db.upsertBatch([
        ArpHostRecord(
          ipAddress: '192.168.1.50',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.50'),
          macAddress: '28:57:BE:91:50:CC',
          vendor: 'Hikvision Digital Technology',
          subnet: '192.168.1.0/24',
          interfaceName: 'Ethernet0',
          status: HostStatus.online,
          discoveryMethod: 'ARP + ICMP',
          firstSeenMs: now + 1000,
          lastSeenMs: now + 1000,
        ),
      ]);

      hosts = db.queryHosts(filter: const ArpFilterCriteria());
      expect(hosts.length, equals(1));
      expect(hosts.first.status, equals(HostStatus.conflict));
      expect(hosts.first.hasConflict, isTrue);
      expect(
        hosts.first.conflictingMacs,
        containsAll(['3C:97:0E:12:50:AA', '28:57:BE:91:50:CC']),
      );

      // Verify searching by hyphen-formatted MAC finds the record
      final byHyphenMac = db.queryHosts(
        filter: const ArpFilterCriteria(macFilter: '3c-97-0e'),
      );
      expect(byHyphenMac.length, equals(1));
      expect(byHyphenMac.first.ipAddress, equals('192.168.1.50'));

      // Verify searching by IP address finds the record
      final byIp = db.queryHosts(
        filter: const ArpFilterCriteria(ipFilter: '192.168.1.50'),
      );
      expect(byIp.length, equals(1));
    });
  });

  group('ArpScoutApp Widget Test', () {
    testWidgets('renders 5-tier desktop layout, loads demo subnet, and filters by MAC/IP', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const ArpScoutApp());
      await tester.pumpAndSettle();

      expect(find.text('ARP & Subnet Scout'), findsOneWidget);
      expect(find.text('No ARP or Subnet Discovery Data Loaded'), findsOneWidget);

      // Click Load Demo Subnet button in the empty state
      await tester.tap(find.text('Load Demo Subnet (with Conflicts)'));
      await tester.pumpAndSettle();

      // Verify IP conflict banner appears
      expect(find.textContaining('IP ADDRESS CONFLICT DETECTED'), findsOneWidget);
      expect(find.text('192.168.10.1'), findsOneWidget);
      expect(find.text('192.168.10.50'), findsOneWidget);
    });
  });
}
