import 'package:arp_scout/domain/models/arp_host_record.dart';
import 'package:arp_scout/domain/models/host_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Table context menu renders with dynamic constraints and no overflow', (tester) async {
    const record = ArpHostRecord(
      ipAddress: '10.101.1.21',
      ipNumeric: 174391573,
      macAddress: 'F8:0F:F9:90:89:2F',
      vendor: 'Unknown OUI (F8:0F:F9)',
      hostname: 'Device F8:0F:F9:90:89:2F',
      subnet: '10.101.1.0/24',
      interfaceName: 'eth0',
      status: HostStatus.online,
      discoveryMethod: 'ARP Sweep',
      firstSeenMs: 1000,
      lastSeenMs: 1000,
    );

    final overlayKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            key: overlayKey,
            children: [
              Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    final overlay = overlayKey.currentContext?.findRenderObject() as RenderBox?;
                    showMenu<String>(
                      context: context,
                      position: const RelativeRect.fromLTRB(100, 100, 100, 100),
                      constraints: BoxConstraints(
                        minWidth: 320.0,
                        maxWidth: (overlay != null ? overlay.size.width - 40 : 600.0).clamp(480.0, 720.0),
                      ),
                      items: [
                        PopupMenuItem(
                          value: 'trace_route',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.alt_route, size: 16),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Trace Route in Net Route Scout (${record.ipAddress})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'edit_name',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.edit_note, size: 16),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Edit Device Name (${record.displayName})...',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'simulate_conflict',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.warning_amber_rounded, size: 16),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Simulate Gratuitous ARP Conflict on this IP',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                  child: const Text('Open Menu'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Menu'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Trace Route in Net Route Scout (10.101.1.21)'), findsOneWidget);
    expect(find.text('Edit Device Name (Device F8:0F:F9:90:89:2F)...'), findsOneWidget);
    expect(find.text('Simulate Gratuitous ARP Conflict on this IP'), findsOneWidget);
  });
}
