import 'package:arp_scout/data/repositories/arp_repository.dart';
import 'package:arp_scout/domain/models/arp_host_record.dart';
import 'package:arp_scout/domain/models/host_status.dart';
import 'package:arp_scout/ui/features/scout/view_models/arp_scout_view_model.dart';
import 'package:arp_scout/ui/features/scout/views/arp_detail_panel.dart';
import 'package:arp_scout/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';

void main() {
  group('ArpDetailPanel Widget Tests', () {
    late ArpRepository repository;
    late ArpScoutViewModel viewModel;

    setUp(() async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
      repository = ArpRepository();
      viewModel = ArpScoutViewModel(repository: repository);
      await Future.delayed(const Duration(milliseconds: 10));
    });

    tearDown(() {
      viewModel.dispose();
    });

    Widget createTestWidget() {
      return ChangeNotifierProvider<ArpScoutViewModel>.value(
        value: viewModel,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: const Scaffold(
            body: Column(
              children: [
                Expanded(child: SizedBox()),
                ArpDetailPanel(),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('renders SizedBox.shrink when no record is selected', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(TabBar), findsNothing);
      expect(find.text('Summary & Conflicts'), findsNothing);
    });

    testWidgets('displays host telemetry, tabs, and action buttons when record is selected', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const host = ArpHostRecord(
        ipAddress: '192.168.1.55',
        ipNumeric: 3232235831,
        macAddress: '00:1A:2B:3C:4D:5E',
        vendor: 'Cisco Systems, Inc.',
        hostname: 'core-switch.corp',
        customName: 'Core Switch Alpha',
        subnet: '192.168.1.0/24',
        interfaceName: 'Ethernet0',
        status: HostStatus.online,
        discoveryMethod: 'ARP + ICMP',
        rttMs: 1.50,
        ttl: 255,
        firstSeenMs: 10000,
        lastSeenMs: 20000,
        notes: 'Primary distribution layer switch',
      );

      viewModel.selectRecord(host);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Top bar telemetry
      expect(find.text('192.168.1.55'), findsAtLeastNWidgets(1));
      expect(find.text('00:1A:2B:3C:4D:5E'), findsAtLeastNWidgets(1));
      expect(find.text('Core Switch Alpha'), findsAtLeastNWidgets(1));
      expect(find.text('(Cisco Systems, Inc.)'), findsOneWidget);

      // Tabs
      expect(find.text('Summary & Conflicts'), findsOneWidget);
      expect(find.text('ARP Hex Inspector'), findsOneWidget);
      expect(find.text('CLI & Raw ARP'), findsOneWidget);

      // Detail fields in Tab 1
      expect(find.text('core-switch.corp'), findsOneWidget);
      expect(find.text('1.50 ms'), findsOneWidget);
      expect(find.text('Network Gear / Cisco / Solaris (TTL 255)'), findsOneWidget);
      expect(find.text('DIAGNOSTIC NOTES: Primary distribution layer switch'), findsOneWidget);

      // Close button closes inspector
      await tester.tap(find.byTooltip('Close Detail Inspector'));
      await tester.pumpAndSettle();

      expect(viewModel.selectedRecord, isNull);
      expect(find.byType(TabBar), findsNothing);
    });

    testWidgets('renders conflict banner when host has conflict status', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const conflictHost = ArpHostRecord(
        ipAddress: '192.168.10.50',
        ipNumeric: 3232238130,
        macAddress: '3C:97:0E:12:50:AA',
        vendor: 'Intel Corporate',
        subnet: '192.168.10.0/24',
        interfaceName: 'Ethernet0',
        status: HostStatus.conflict,
        discoveryMethod: 'ARP + ICMP',
        conflictingMacs: ['3C:97:0E:12:50:AA', '28:57:BE:91:50:CC'],
        firstSeenMs: 10000,
        lastSeenMs: 20000,
        notes: 'IP CONFLICT: Claimed by 3C:97:0E:12:50:AA vs 28:57:BE:91:50:CC',
      );

      viewModel.selectRecord(conflictHost);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.textContaining('L2/L3 IP ADDRESS CONFLICT DIAGNOSTIC'), findsOneWidget);
      expect(find.textContaining('3C:97:0E:12:50:AA'), findsAtLeastNWidgets(1));
      expect(find.textContaining('28:57:BE:91:50:CC'), findsAtLeastNWidgets(1));
    });

    testWidgets('switching to ARP Hex Inspector tab renders frame breakdown', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const host = ArpHostRecord(
        ipAddress: '192.168.1.100',
        ipNumeric: 3232235876,
        macAddress: '00:11:22:33:44:55',
        vendor: 'Test Vendor',
        subnet: '192.168.1.0/24',
        interfaceName: 'Ethernet0',
        status: HostStatus.online,
        discoveryMethod: 'ARP',
        firstSeenMs: 0,
        lastSeenMs: 0,
      );

      viewModel.selectRecord(host);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap on Tab 2: ARP Hex Inspector
      await tester.tap(find.text('ARP Hex Inspector'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ETHERNET II + ARP FRAME PAYLOAD'), findsOneWidget);
      expect(find.text('Sender: 00:11:22:33:44:55 (192.168.1.100)'), findsOneWidget);
    });

    testWidgets('switching to CLI & Raw ARP tab renders command and line info', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const host = ArpHostRecord(
        ipAddress: '192.168.1.100',
        ipNumeric: 3232235876,
        macAddress: '00:11:22:33:44:55',
        vendor: 'Test Vendor',
        subnet: '192.168.1.0/24',
        interfaceName: 'Ethernet0',
        status: HostStatus.online,
        discoveryMethod: 'ARP',
        rawArpLine: '192.168.1.100 lladdr 00:11:22:33:44:55 REACHABLE',
        firstSeenMs: 0,
        lastSeenMs: 0,
      );

      viewModel.selectRecord(host);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap on Tab 3: CLI & Raw ARP
      await tester.tap(find.text('CLI & Raw ARP'));
      await tester.pumpAndSettle();

      expect(find.text('RAW OS ARP ENTRY'), findsOneWidget);
      expect(find.text('192.168.1.100 lladdr 00:11:22:33:44:55 REACHABLE'), findsOneWidget);
    });
  });
}
