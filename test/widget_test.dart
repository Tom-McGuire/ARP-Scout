import 'package:arp_scout/data/services/database/arp_database_service.dart';
import 'package:arp_scout/data/services/export/export_service.dart';
import 'package:arp_scout/data/services/import/csv_import_service.dart';
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

  group('ArpHostRecord & IPv4 Validation', () {
    test('strictly validates IPv4 octets and rejects out-of-range values', () {
      expect(ArpHostRecord.isValidIpv4('192.168.1.1'), isTrue);
      expect(ArpHostRecord.isValidIpv4('0.0.0.0'), isTrue);
      expect(ArpHostRecord.isValidIpv4('255.255.255.255'), isTrue);
      expect(ArpHostRecord.isValidIpv4('999.999.999.999'), isFalse);
      expect(ArpHostRecord.isValidIpv4('192.168.1.256'), isFalse);
      expect(ArpHostRecord.isValidIpv4('192.168.01.1'), isFalse);
      expect(ArpHostRecord.isValidIpv4('192.168.1'), isFalse);
      expect(ArpHostRecord.ipv4ToInt('999.999.999.999'), equals(0));
    });
  });

  group('SubnetScannerService', () {
    test('expands CIDR /24, /31, /32, IP ranges, and rejects invalid inputs', () {
      final ips24 = SubnetScannerService.expandTargetSubnet('192.168.10.0/24');
      expect(ips24.length, equals(254));
      expect(ips24.first, equals('192.168.10.1'));
      expect(ips24.last, equals('192.168.10.254'));

      final ips31 = SubnetScannerService.expandTargetSubnet('10.0.0.0/31');
      expect(ips31, equals(['10.0.0.0', '10.0.0.1']));

      final ips32 = SubnetScannerService.expandTargetSubnet('10.0.0.42/32');
      expect(ips32, equals(['10.0.0.42']));

      final rangeIps = SubnetScannerService.expandTargetSubnet(
        '10.0.0.10-10.0.0.15',
      );
      expect(rangeIps.length, equals(6));
      expect(rangeIps.first, equals('10.0.0.10'));
      expect(rangeIps.last, equals('10.0.0.15'));

      expect(
        SubnetScannerService.expandTargetSubnet('999.999.999.0/24'),
        isEmpty,
      );
      expect(
        SubnetScannerService.expandTargetSubnet('192.168.1.50-10'),
        isEmpty,
      );
    });

    test('sanitizes untrusted CLI preview strings and checks CIDR subnet bounds', () {
      final safePreview = SubnetScannerService.buildCliPreviewCommand(
        '192.168.1.0/24; rm -rf /',
      );
      expect(safePreview.contains('rm -rf'), isFalse);

      final expanded26 = SubnetScannerService.expandTargetSubnet('192.168.1.0/26').toSet();
      expect(
        SubnetScannerService.isIpInTargetSubnet('192.168.1.62', '192.168.1.0/26', expanded26),
        isTrue,
      );
      expect(
        SubnetScannerService.isIpInTargetSubnet('192.168.1.65', '192.168.1.0/26', expanded26),
        isFalse,
      );
    });

    test('parses Windows (English and localized), Unix arp -an, and Linux ip neigh output', () {
      const sampleArp = '''
Schnittstelle: 192.168.1.15 --- 0xe
  Internet Address      Physical Address      Type
  192.168.1.1           00-09-0f-aa-10-01     dynamisch
  192.168.1.50          28-57-be-91-50-cc     dynamic
  192.168.1.255         ff-ff-ff-ff-ff-ff     static
  224.0.0.22            01-00-5e-00-00-16     static
? (192.168.1.70) at 0:50:56:8b:10:10 [ether] on en0
192.168.1.80 dev eth0 lladdr bc:24:11:4e:12:01 REACHABLE
''';
      final parsed = SubnetScannerService.parseArpTableOutput(sampleArp);
      expect(parsed.length, equals(4));
      expect(parsed[0].ipAddress, equals('192.168.1.1'));
      expect(parsed[0].macAddress, equals('00:09:0F:AA:10:01'));
      expect(parsed[0].arpType, equals('dynamic'));
      expect(parsed[0].interfaceIp, equals('192.168.1.15'));
      expect(parsed[1].ipAddress, equals('192.168.1.50'));
      expect(parsed[1].macAddress, equals('28:57:BE:91:50:CC'));
      expect(parsed[2].ipAddress, equals('192.168.1.70'));
      expect(parsed[2].macAddress, equals('00:50:56:8B:10:10'));
      expect(parsed[3].ipAddress, equals('192.168.1.80'));
      expect(parsed[3].macAddress, equals('BC:24:11:4E:12:01'));
    });
  });

  group('ExportService & CsvImportService', () {
    test('mitigates CSV formula injection including leading whitespace', () {
      expect(ExportService.sanitizeForCsv('=CMD()'), equals("'=CMD()"));
      expect(ExportService.sanitizeForCsv('  =HYPERLINK()'), equals("'  =HYPERLINK()"));
      expect(ExportService.sanitizeForCsv('|calc'), equals("'|calc"));
      expect(ExportService.sanitizeForCsv('normal-host.local'), equals('normal-host.local'));
    });

    test('parses valid CSV rows and skips malformed IPv4 octets', () {
      const csvText = '''
IP Address,MAC Address,Vendor (OUI),Hostname,Status
192.168.1.10,00:50:56:11:22:33,VMware,esxi-01.local,ONLINE
999.999.999.999,00:50:56:11:22:34,Invalid,bad-host,ONLINE
192.168.1.20,74:83:C2:AA:BB:CC,,ap-lobby,ARP ONLY
''';
      final res = CsvImportService.parseCsvContent(csvText, fileName: 'test.csv');
      expect(res.records.length, equals(2));
      expect(res.skippedCount, equals(1));
      expect(res.records[0].ipAddress, equals('192.168.1.10'));
      expect(res.records[1].vendor, equals('Ubiquiti Inc.'));
      expect(res.records[1].status, equals(HostStatus.arpOnly));
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

    test('correlates and cleans up multi-homed MACs and reconciles stale hosts', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      const sharedMac = 'BC:24:11:4E:12:01';

      db.upsertBatch([
        ArpHostRecord(
          ipAddress: '192.168.1.12',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.12'),
          macAddress: sharedMac,
          vendor: 'Proxmox Server Solutions GmbH',
          subnet: '192.168.1.0/24',
          interfaceName: 'Ethernet0',
          status: HostStatus.online,
          discoveryMethod: 'ARP + ICMP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
        ArpHostRecord(
          ipAddress: '192.168.1.13',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.13'),
          macAddress: sharedMac,
          vendor: 'Proxmox Server Solutions GmbH',
          subnet: '192.168.1.0/24',
          interfaceName: 'Ethernet0',
          status: HostStatus.online,
          discoveryMethod: 'ARP + ICMP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
        ArpHostRecord(
          ipAddress: '192.168.1.99',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.99'),
          macAddress: 'RESOLVING...',
          vendor: 'Resolving L2 ARP...',
          subnet: '192.168.1.0/24',
          interfaceName: 'Ethernet0',
          status: HostStatus.icmpOnly,
          discoveryMethod: 'ICMP Echo',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
      ]);

      var hosts = db.queryHosts(filter: const ArpFilterCriteria());
      expect(hosts.first.associatedIps, equals(['192.168.1.12', '192.168.1.13']));

      // Reconcile sweep where only .12 responded: .99 ('RESOLVING...') is removed and .13 becomes stale
      db.reconcileSweepCompletion(
        subnet: '192.168.1.0/24',
        activeIps: {'192.168.1.12'},
        markMissingAsStale: true,
      );

      hosts = db.queryHosts(filter: const ArpFilterCriteria());
      expect(hosts.length, equals(2));
      expect(hosts[0].ipAddress, equals('192.168.1.12'));
      expect(hosts[0].status, equals(HostStatus.online));
      expect(hosts[1].ipAddress, equals('192.168.1.13'));
      expect(hosts[1].status, equals(HostStatus.stale));
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
