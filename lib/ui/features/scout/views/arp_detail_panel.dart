import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../data/services/oui/oui_lookup_service.dart';
import '../../../../domain/models/arp_host_record.dart';
import '../view_models/arp_scout_view_model.dart';

class ArpDetailPanel extends StatefulWidget {
  const ArpDetailPanel({super.key});

  @override
  State<ArpDetailPanel> createState() => _ArpDetailPanelState();
}

class _ArpDetailPanelState extends State<ArpDetailPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DateFormat _timeFormatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ArpScoutViewModel>();
    final record = vm.selectedRecord;

    if (record == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Inspector Header Bar with Tabs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                // Status Pill
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: record.status.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: record.status.color, width: 1),
                  ),
                  child: Text(
                    record.status.label.toUpperCase(),
                    style: TextStyle(
                      color: record.status.color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  record.ipAddress,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                const Text('↔', style: TextStyle(color: Colors.grey)),
                const SizedBox(width: 8),
                Text(
                  record.macAddress,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: Color(0xFF38BDF8),
                  ),
                ),
                const SizedBox(width: 10),
                if (record.customName != null && record.customName!.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      record.customName!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  '(${record.vendor})',
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),

                // Mode Tabs
                SizedBox(
                  width: 390,
                  height: 30,
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    labelStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    unselectedLabelStyle: const TextStyle(fontSize: 11),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Summary & Conflicts'),
                      Tab(text: 'ARP Hex Inspector'),
                      Tab(text: 'CLI & Raw ARP'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Copy Full Summary Button
                IconButton(
                  tooltip: 'Copy Host Summary to Clipboard',
                  icon: const Icon(Icons.copy, size: 15),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    final summary =
                        'Device: ${record.displayName} | IP: ${record.ipAddress} | MAC: ${record.macAddress} | Vendor: ${record.vendor} | Status: ${record.status.label} | Hostname: ${record.hostname ?? "-"} | Conflicts: ${record.conflictingMacs.join(", ")}';
                    Clipboard.setData(ClipboardData(text: summary));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Host L2/L3 summary copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),

                // Close Inspector Button
                IconButton(
                  tooltip: 'Close Detail Inspector',
                  icon: const Icon(Icons.close, size: 16),
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => vm.selectRecord(null),
                ),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryAndConflictTab(context, vm, record),
                _buildHexInspectorTab(record),
                _buildCliAndRawTab(context, vm, record),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryAndConflictTab(
    BuildContext context,
    ArpScoutViewModel vm,
    ArpHostRecord record,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // If an IP conflict exists on this IP, show a prominent Conflict Breakdown Box
          if (record.hasConflict) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'L2/L3 IP ADDRESS CONFLICT DIAGNOSTIC — ${record.conflictingMacs.length} COMPETING MAC ADDRESSES CLAIMING ${record.ipAddress}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFCA5A5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: record.conflictingMacs.map((mac) {
                      final vendor = OuiLookupService.lookupVendor(mac);
                      return InkWell(
                        onTap: () => vm.setMacFilter(mac),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF3E3E42)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.memory,
                                size: 13,
                                color: Color(0xFFEF4444),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                mac,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '($vendor)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Metadata Grid
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _buildEditableMetaItem(
                context,
                vm,
                record,
                'Device Name (Shared Suite)',
                record.displayName,
              ),
              _buildMetaItem('IPv4 Address', record.ipAddress, monospace: true),
              _buildMetaItem(
                'Physical MAC (L2)',
                record.macAddress,
                monospace: true,
              ),
              _buildMetaItem('OUI Hardware Vendor', record.vendor),
              _buildMetaItem('Hostname (PTR)', record.hostname ?? 'Unresolved'),
              _buildMetaItem('Subnet', record.subnet, monospace: true),
              _buildMetaItem('Interface', record.interfaceName),
              _buildMetaItem('Discovery Method', record.discoveryMethod),
              _buildMetaItem('ARP Cache Type', record.arpType.toUpperCase()),
              _buildMetaItem(
                'ICMP RTT',
                record.rttMs != null
                    ? '${record.rttMs!.toStringAsFixed(2)} ms'
                    : 'No ICMP Reply',
                monospace: true,
              ),
              _buildMetaItem('OS / TTL Fingerprint', record.osHintFromTtl),
              _buildMetaItem(
                'First Seen',
                _timeFormatter.format(record.firstSeen),
                monospace: true,
              ),
              _buildMetaItem(
                'Last Seen',
                _timeFormatter.format(record.lastSeen),
                monospace: true,
              ),
              _buildMetaItem(
                'Observations',
                '${record.responseCount} sweeps',
                monospace: true,
              ),
              if (record.associatedIps.length > 1)
                _buildMetaItem(
                  'Multi-Homed IPs Sharing MAC',
                  record.associatedIps.join(', '),
                  monospace: true,
                ),
            ],
          ),
          if (record.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Text(
              'DIAGNOSTIC NOTES: ${record.notes}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  /// Canonical 16-bytes-per-line Hex / ASCII Inspector from Section 5.4
  Widget _buildHexInspectorTab(ArpHostRecord record) {
    final frameBytes = record.toSyntheticArpFrameBytes();
    final formattedHexDump = _formatHexAsciiDump(frameBytes);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ETHERNET II + ARP FRAME PAYLOAD (42 BYTES — ETHERTYPE 0x0806)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                'Sender: ${record.macAddress} (${record.ipAddress})',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Color(0xFF38BDF8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2C2C2C)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  formattedHexDump,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.35,
                    color: Color(0xFFE2E8F0),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCliAndRawTab(
    BuildContext context,
    ArpScoutViewModel vm,
    ArpHostRecord record,
  ) {
    final targetSubnet = record.subnet.isNotEmpty
        ? record.subnet
        : '${record.ipAddress}/32';
    final cliCommand = vm.scanProgress.generatedCommand.isNotEmpty
        ? vm.scanProgress.generatedCommand
        : 'arp-scout sweep $targetSubnet --interface "${record.interfaceName}" --json';

    final rawArp = record.rawArpLine.isNotEmpty
        ? record.rawArpLine
        : '${record.ipAddress}    ${record.macAddress}    ${record.arpType}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'EQUIVALENT CLI SCAN COMMAND',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Copy CLI Command',
                icon: const Icon(Icons.copy, size: 14),
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: cliCommand));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('CLI Command copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2C2C2C)),
            ),
            child: SelectableText(
              cliCommand,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF38BDF8),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'RAW OS ARP ENTRY',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2C2C2C)),
            ),
            child: SelectableText(
              rawArp,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFFD4D4D4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatHexAsciiDump(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var offset = 0; offset < bytes.length; offset += 16) {
      final lineLen = (offset + 16 <= bytes.length)
          ? 16
          : (bytes.length - offset);
      final offsetHex = offset.toRadixString(16).padLeft(4, '0');
      final hexPart = StringBuffer();
      final asciiPart = StringBuffer();

      for (var i = 0; i < 16; i++) {
        if (i == 8) hexPart.write(' ');
        if (i < lineLen) {
          final b = bytes[offset + i];
          hexPart.write('${b.toRadixString(16).padLeft(2, '0')} ');
          asciiPart.write((b >= 32 && b <= 126) ? String.fromCharCode(b) : '.');
        } else {
          hexPart.write('   ');
        }
      }

      buffer.writeln('$offsetHex   $hexPart  $asciiPart');
    }
    return buffer.toString().trimRight();
  }

  Widget _buildEditableMetaItem(
    BuildContext context,
    ArpScoutViewModel vm,
    ArpHostRecord record,
    String label,
    String value,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        InkWell(
          onTap: () => _showEditDeviceNameDialog(context, vm, record),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFF3E3E42)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: record.customName != null ? FontWeight.bold : FontWeight.w500,
                    color: record.customName != null ? const Color(0xFF38BDF8) : Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.edit_outlined,
                  size: 13,
                  color: Color(0xFF38BDF8),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetaItem(String label, String value, {bool monospace = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            fontFamily: monospace ? 'monospace' : null,
          ),
        ),
      ],
    );
  }

  Future<void> _showEditDeviceNameDialog(
    BuildContext context,
    ArpScoutViewModel vm,
    ArpHostRecord record,
  ) async {
    final initialName = record.customName ?? (record.hostname ?? '');
    final controller = TextEditingController(text: initialName);
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Row(
            children: [
              Icon(Icons.devices, size: 20, color: Color(0xFF38BDF8)),
              SizedBox(width: 8),
              Text('Edit Device Name', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Updates hardware identity across all Network Suite tools for MAC:',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF3E3E42)),
                    ),
                    child: Text(
                      '${record.macAddress} • ${record.vendor}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: controller,
                    autofocus: true,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Friendly Device Name',
                      hintText: 'e.g. Living Room Apple TV, Core Switch',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label_outline, size: 18),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Device name cannot be empty';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Save Device Name'),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  final newName = controller.text.trim();
                  vm.updateDeviceName(record.macAddress, newName);
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Updated name for ${record.macAddress} to "$newName" in Network Suite',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}
