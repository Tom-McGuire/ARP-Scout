import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../view_models/arp_scout_view_model.dart';

class ArpControlBar extends StatefulWidget {
  const ArpControlBar({super.key});

  @override
  State<ArpControlBar> createState() => _ArpControlBarState();
}

class _ArpControlBarState extends State<ArpControlBar> {
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ArpScoutViewModel>();
    final progress = vm.scanProgress;
    final isScanning = progress.isScanning;
    final isWatching = progress.isContinuousWatch;
    final conflictCount = vm.conflictCount;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // TIER 1: Top Control Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // App Icon & Title
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.asset(
                    'assets/app_icon.png',
                    width: 28,
                    height: 28,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ARP & Subnet Scout',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      'L2/L3 Discovery • OUI Lookup • Conflict Detector',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(width: 18),

                // Primary Action: Sweep Subnet / Stop Scan
                FilledButton.icon(
                  onPressed: () {
                    if (isScanning) {
                      vm.stopScan();
                    } else {
                      vm.startSubnetScan();
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: isScanning
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                  icon: Icon(
                    isScanning ? Icons.stop : Icons.radar,
                    size: 17,
                  ),
                  label: Text(
                    isScanning ? 'Stop Sweep' : 'Sweep Subnet',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Instant L2 ARP Cache Read Button
                FilledButton.tonalIcon(
                  onPressed: isScanning
                      ? null
                      : () => vm.startSubnetScan(arpCacheOnly: true),
                  icon: const Icon(Icons.bolt, size: 16),
                  label: const Text(
                    'Read ARP Cache',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Continuous Watch Mode Toggle
                OutlinedButton.icon(
                  onPressed: () => vm.toggleContinuousWatch(),
                  icon: Icon(
                    isWatching ? Icons.visibility : Icons.visibility_outlined,
                    size: 15,
                    color: isWatching ? const Color(0xFF10B981) : Colors.grey,
                  ),
                  label: Text(
                    isWatching ? 'Watching (15s)' : 'Watch Mode',
                    style: TextStyle(
                      fontSize: 12,
                      color: isWatching
                          ? const Color(0xFF10B981)
                          : Colors.white70,
                      fontWeight: isWatching
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isWatching
                          ? const Color(0xFF10B981)
                          : const Color(0xFF3E3E42),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Network Interface Selector
                const Text(
                  'Interface:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 6),
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252526),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF3E3E42)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<NetworkAdapterInfo>(
                      value: vm.adapters.contains(vm.selectedAdapter)
                          ? vm.selectedAdapter
                          : vm.adapters.first,
                      isDense: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 18),
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      dropdownColor: const Color(0xFF252526),
                      onChanged: isScanning
                          ? null
                          : (adapter) {
                              if (adapter != null) {
                                vm.selectAdapter(adapter);
                              }
                            },
                      items: vm.adapters.map((adapter) {
                        IconData icon = Icons.lan_outlined;
                        if (adapter.isAllInterfaces) {
                          icon = Icons.public;
                        } else if (adapter.name.toLowerCase().contains(
                              'wi-fi',
                            ) ||
                            adapter.name.toLowerCase().contains('wlan')) {
                          icon = Icons.wifi;
                        }
                        return DropdownMenuItem<NetworkAdapterInfo>(
                          value: adapter,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                icon,
                                size: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 6),
                              Text(adapter.displayName),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh network interfaces',
                  icon: const Icon(Icons.refresh, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  onPressed: isScanning ? null : () => vm.refreshAdapters(),
                ),
                const SizedBox(width: 10),

                // Target Subnet Dropdown Selector
                const Text(
                  'Subnet:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 6),
                Builder(
                  builder: (context) {
                    final currentSubnet = progress.targetSubnet;
                    final base = vm.selectedAdapter.isAllInterfaces
                        ? '192.168.1'
                        : vm.selectedAdapter.ipAddress
                              .split('.')
                              .take(3)
                              .join('.');
                    final availableSubnets = <String>{
                      currentSubnet,
                      '$base.0/24',
                      '$base.1-50',
                      '$base.0/26',
                      '192.168.1.0/24',
                      '10.0.0.0/24',
                      '172.16.0.0/24',
                    }.toList();

                    return Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF252526),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF3E3E42)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currentSubnet,
                          isDense: true,
                          icon: const Icon(Icons.arrow_drop_down, size: 18),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                          ),
                          dropdownColor: const Color(0xFF252526),
                          onChanged: isScanning
                              ? null
                              : (val) {
                                  if (val == '__custom__') {
                                    _showCustomSubnetDialog(context, vm);
                                  } else if (val != null) {
                                    vm.updateTargetSubnet(val);
                                  }
                                },
                          items: [
                            ...availableSubnets.map((cidr) {
                              return DropdownMenuItem<String>(
                                value: cidr,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.hub_outlined,
                                      size: 14,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      cidr,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const DropdownMenuItem<String>(
                              value: '__custom__',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.edit_outlined,
                                    size: 14,
                                    color: Color(0xFF38BDF8),
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Custom CIDR / Range...',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF38BDF8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Enter custom subnet or IP range',
                  icon: const Icon(Icons.edit_outlined, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  onPressed: isScanning
                      ? null
                      : () => _showCustomSubnetDialog(context, vm),
                ),
                const SizedBox(width: 14),

                // Loaded CSV file badge if present
                if (vm.loadedFileName != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.insert_drive_file_outlined,
                          size: 13,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 5),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 130),
                          child: Text(
                            vm.loadedFileName!,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => vm.closeLoadedFile(),
                          child: const Icon(
                            Icons.close,
                            size: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Demo Topology Button
                OutlinedButton.icon(
                  onPressed: () {
                    vm.loadDemoTopology();
                  },
                  icon: const Icon(Icons.auto_awesome, size: 15),
                  label: const Text(
                    'Demo Subnet',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Simulate Conflict Button (for testing L2 conflict detection)
                Tooltip(
                  message:
                      'Inject a simulated Gratuitous ARP MAC collision on an existing IP',
                  child: OutlinedButton.icon(
                    onPressed: () {
                      vm.simulateRogueMacConflict();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Simulated Gratuitous ARP conflict injected — check IP CONFLICT alerts.',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.warning_amber_rounded,
                      size: 15,
                      color: Color(0xFFF59E0B),
                    ),
                    label: const Text(
                      'Test Conflict',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Import CSV Button
                FilledButton.tonalIcon(
                  onPressed: vm.isImporting
                      ? null
                      : () => _handleImportCsv(context, vm),
                  icon: const Icon(Icons.file_open_outlined, size: 15),
                  label: const Text('Open CSV', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Clear Button
                OutlinedButton.icon(
                  onPressed: vm.unfilteredTotalCount == 0
                      ? null
                      : () => _confirmClear(context, vm),
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text('Clear', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade300,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: 4),

                // Export Menu
                PopupMenuButton<String>(
                  tooltip: 'Export Discovered Hosts',
                  enabled: vm.hosts.isNotEmpty,
                  icon: const Icon(Icons.file_download_outlined, size: 20),
                  onSelected: (val) async {
                    if (val == 'csv') {
                      final path = await vm.exportCsv();
                      if (path != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Exported CSV to: $path')),
                        );
                      }
                    } else if (val == 'json') {
                      final path = await vm.exportJson();
                      if (path != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Exported JSON to: $path')),
                        );
                      }
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'csv',
                      child: Row(
                        children: [
                          Icon(Icons.table_chart, size: 16),
                          SizedBox(width: 8),
                          Text('Export Table as CSV'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'json',
                      child: Row(
                        children: [
                          Icon(Icons.code, size: 16),
                          SizedBox(width: 8),
                          Text('Export Table as JSON'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // TIER 2A: Live Scan Progress Banner
          if (isScanning)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFF007ACC).withValues(alpha: 0.18),
              child: Row(
                children: [
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    progress.currentPhase,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                  const SizedBox(width: 14),
                  if (progress.totalHosts > 0)
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress.progressFraction,
                          minHeight: 6,
                          backgroundColor: const Color(0xFF252526),
                          color: const Color(0xFF007ACC),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 12),
                  Text(
                    'Target: ${progress.targetSubnet}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),

          // TIER 2B: Global IP Address Conflict Alert Banner
          if (conflictCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.16),
                border: Border(
                  top: BorderSide(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Color(0xFFEF4444),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'IP ADDRESS CONFLICT DETECTED: $conflictCount IPv4 ${conflictCount == 1 ? "address is" : "addresses are"} claimed by multiple physical MAC addresses on this subnet!',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFCA5A5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => vm.toggleConflictsOnly(),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: vm.filter.conflictsOnly
                            ? const Color(0xFFEF4444)
                            : const Color(0xFFEF4444).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFEF4444)),
                      ),
                      child: Text(
                        vm.filter.conflictsOnly
                            ? 'SHOW ALL HOSTS'
                            : 'ISOLATE CONFLICTS ($conflictCount)',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // TIER 2C: Error Banner
          if (progress.lastError != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.red.shade900.withValues(alpha: 0.85),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      progress.lastError!,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy error message',
                    icon: const Icon(
                      Icons.copy,
                      size: 13,
                      color: Colors.white70,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: progress.lastError!),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Dismiss error banner',
                    icon: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white70,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 22,
                    ),
                    onPressed: () => vm.dismissError(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleImportCsv(
    BuildContext context,
    ArpScoutViewModel vm,
  ) async {
    bool replaceExisting = false;
    if (vm.unfilteredTotalCount > 0) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import ARP / Subnet CSV'),
          content: const Text(
            'Would you like to merge the imported CSV with the current SQLite table (which also checks for IP conflicts against existing rows) or replace the session?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Merge & Detect Conflicts'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Replace Table'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      replaceExisting = choice;
    }

    final result = await vm.importCsvFile(replaceExisting: replaceExisting);
    if (result != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result.records.length} hosts from ${result.fileName}'
            '${result.skippedCount > 0 ? " (${result.skippedCount} skipped)" : ""}',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _confirmClear(BuildContext context, ArpScoutViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Discovered ARP Table?'),
        content: const Text(
          'This will clear all discovered IP-to-MAC associations and conflict history from the active SQLite database.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              vm.clearHosts();
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomSubnetDialog(
    BuildContext context,
    ArpScoutViewModel vm,
  ) async {
    final controller = TextEditingController(text: vm.scanProgress.targetSubnet);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.hub_outlined, size: 20, color: Color(0xFF007ACC)),
            SizedBox(width: 8),
            Text('Custom Subnet / Range'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter an IPv4 CIDR subnet or start-end IP range to sweep:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  hintText: 'e.g. 192.168.1.0/24 or 10.0.0.1-50',
                  prefixIcon: Icon(Icons.lan_outlined, size: 16),
                ),
                onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
              ),
              const SizedBox(height: 10),
              const Text(
                'Supported formats:\n• CIDR: 192.168.1.0/24, 10.101.1.0/26\n• Range: 192.168.1.1-192.168.1.50 or 192.168.1.1-50\n• Single Host: 192.168.1.10',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white54,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Apply Subnet'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (result != null && result.isNotEmpty) {
      vm.updateTargetSubnet(result);
    }
  }
}
