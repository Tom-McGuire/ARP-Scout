import 'package:arp_scout/data/repositories/arp_repository.dart';
import 'package:arp_scout/data/services/database/arp_database_service.dart';
import 'package:arp_scout/domain/models/arp_host_record.dart';
import 'package:arp_scout/domain/models/host_status.dart';
import 'package:arp_scout/ui/features/scout/view_models/arp_scout_view_model.dart';
import 'package:arp_scout/ui/features/scout/views/arp_filter_bar.dart';
import 'package:arp_scout/ui/features/scout/views/dialogs/device_library_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';

void main() {
  group('ArpFilterBar Device Quick-Filter & Status Triage UI Tests', () {
    late ArpDatabaseService db;
    late ArpRepository repository;
    late ArpScoutViewModel viewModel;

    setUp(() async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
      db = ArpDatabaseService();
      repository = ArpRepository(databaseService: db);

      SharedDeviceDatabase.instance.upsertDevice(
        SharedDevice(
          macAddress: '00:1A:2B:3C:4D:5E',
          name: 'Core Switch',
          deviceType: 'switch',
          sourceApp: 'Test',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final now = DateTime.now().millisecondsSinceEpoch;
      db.upsertBatch([
        ArpHostRecord(
          ipAddress: '192.168.1.1',
          ipNumeric: ArpHostRecord.ipv4ToInt('192.168.1.1'),
          macAddress: '00:1A:2B:3C:4D:5E',
          vendor: 'Cisco',
          subnet: '192.168.1.0/24',
          interfaceName: 'eth0',
          status: HostStatus.online,
          discoveryMethod: 'ARP',
          firstSeenMs: now,
          lastSeenMs: now,
        ),
      ]);

      viewModel = ArpScoutViewModel(repository: repository);
      await Future.delayed(const Duration(milliseconds: 30));
    });

    tearDown(() {
      viewModel.dispose();
    });

    Widget createFilterBarWidget() {
      return MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ChangeNotifierProvider<ArpScoutViewModel>.value(
            value: viewModel,
            child: const ArpFilterBar(),
          ),
        ),
      );
    }

    testWidgets('renders Status Triage above Devices row, with CircleAvatar dots', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createFilterBarWidget());
      await tester.pumpAndSettle();

      // Check Status Triage header and Devices header
      final triageFinder = find.text('STATUS TRIAGE:');
      final devicesFinder = find.text('DEVICES:');
      expect(triageFinder, findsOneWidget);
      expect(devicesFinder, findsOneWidget);

      // Verify Status Triage is vertically above Devices
      final triageTop = tester.getTopLeft(triageFinder).dy;
      final devicesTop = tester.getTopLeft(devicesFinder).dy;
      expect(triageTop, lessThan(devicesTop));

      // Verify CircleAvatar dot avatars are rendered for chips
      final circleAvatars = find.byType(CircleAvatar);
      expect(circleAvatars, findsWidgets);

      // Check that Core Switch (1) pill is rendered in Devices row
      expect(find.text('Core Switch (1)'), findsOneWidget);

      // Check Auto-Detected switch is present
      expect(find.text('Auto-Detected'), findsOneWidget);

      // Check Manage chip is present
      expect(find.text('Manage'), findsOneWidget);
    });

    testWidgets('clicking Manage chip opens DeviceLibraryDialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createFilterBarWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Manage'));
      await tester.pumpAndSettle();

      // Verify DeviceLibraryDialog opens
      expect(find.byType(DeviceLibraryDialog), findsOneWidget);
      expect(find.text('Custom Library'), findsOneWidget);
      expect(find.text('Core Switch'), findsOneWidget);
    });

    testWidgets('tapping device pill toggles active selection', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(createFilterBarWidget());
      await tester.pumpAndSettle();

      expect(viewModel.filter.selectedDeviceMacs, isEmpty);

      // Tap on Core Switch pill
      await tester.tap(find.text('Core Switch (1)'));
      await tester.pumpAndSettle();

      expect(viewModel.filter.selectedDeviceMacs, contains('00:1A:2B:3C:4D:5E'));
    });
  });
}
