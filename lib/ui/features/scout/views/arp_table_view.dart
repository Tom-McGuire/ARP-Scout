import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/arp_host_record.dart';
import '../../../../domain/models/host_status.dart';
import '../view_models/arp_scout_view_model.dart';

enum ArpTableColumn {
  status('Status', 'status', 135.0, 95.0),
  ip('IP Address', 'ip_numeric', 135.0, 100.0),
  mac('MAC Address', 'mac_address', 155.0, 120.0),
  vendor('Vendor (OUI)', 'vendor', 220.0, 120.0),
  hostname('Device Name / Host', 'custom_name', 195.0, 110.0),
  rtt('RTT', 'rtt_ms', 80.0, 60.0),
  ttl('TTL / OS Hint', 'ttl', 140.0, 85.0),
  discovery('Discovery', 'discovery_method', 120.0, 85.0),
  lastSeen('Last Seen', 'last_seen_ms', 150.0, 105.0),
  notes('Diagnostic Notes / Conflict Summary', 'id', 320.0, 150.0);

  const ArpTableColumn(
    this.label,
    this.sortKey,
    this.defaultWidth,
    this.minWidth,
  );

  final String label;
  final String sortKey;
  final double defaultWidth;
  final double minWidth;
}

class ArpTableView extends StatefulWidget {
  const ArpTableView({super.key});

  @override
  State<ArpTableView> createState() => _ArpTableViewState();
}

class _ArpTableViewState extends State<ArpTableView> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  late Map<ArpTableColumn, double> _columnWidths;
  final DateFormat _timeFormatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  @override
  void initState() {
    super.initState();
    _columnWidths = {
      for (final col in ArpTableColumn.values) col: col.defaultWidth,
    };
    _verticalScrollController.addListener(_onVerticalScroll);
  }

  void _onVerticalScroll() {
    if (!_verticalScrollController.hasClients) return;
    final maxScroll = _verticalScrollController.position.maxScrollExtent;
    final currentScroll = _verticalScrollController.position.pixels;
    if (maxScroll - currentScroll <= 400) {
      final vm = context.read<ArpScoutViewModel>();
      if (vm.hasMoreHosts && !vm.isLoadingMore) {
        vm.loadMoreHosts();
      }
    }
  }

  @override
  void dispose() {
    _verticalScrollController.removeListener(_onVerticalScroll);
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ArpScoutViewModel>();
    final hosts = vm.hosts;

    if (hosts.isEmpty) {
      return _buildEmptyState(context, vm);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final sumExceptNotes = _columnWidths.entries
            .where((e) => e.key != ArpTableColumn.notes)
            .fold(0.0, (acc, e) => acc + e.value);
        final baseNotesWidth = _columnWidths[ArpTableColumn.notes]!;
        final effectiveNotesWidth = max(
          baseNotesWidth,
          availableWidth - sumExceptNotes - 32.0,
        );

        final effectiveWidths = Map<ArpTableColumn, double>.from(_columnWidths);
        effectiveWidths[ArpTableColumn.notes] = effectiveNotesWidth;

        final totalContentWidth =
            effectiveWidths.values.fold(0.0, (acc, w) => acc + w) + 32.0;
        final totalTableWidth = max(availableWidth, totalContentWidth);

        return Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalTableWidth,
              child: Column(
                children: [
                  _buildHeaderRow(context, vm, effectiveWidths),
                  const Divider(height: 1),
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _verticalScrollController,
                        itemCount: hosts.length + (vm.hasMoreHosts ? 1 : 0),
                        separatorBuilder: (_, index) {
                          if (index >= hosts.length) {
                            return const SizedBox.shrink();
                          }
                          return const Divider(
                            height: 1,
                            indent: 8,
                            endIndent: 8,
                          );
                        },
                        itemBuilder: (context, index) {
                          if (index == hosts.length) {
                            return _buildLoadingMoreIndicator(
                              context,
                              vm,
                              hosts.length,
                            );
                          }
                          final record = hosts[index];
                          return _buildRow(
                            context,
                            vm,
                            record,
                            effectiveWidths,
                          );
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _buildStatusBar(context, vm, hosts.length),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, ArpScoutViewModel vm) {
    final isScanning = vm.scanProgress.isScanning;
    final hasActiveFilter =
        vm.filter.searchQuery.isNotEmpty ||
        vm.filter.ipFilter.isNotEmpty ||
        vm.filter.macFilter.isNotEmpty ||
        vm.filter.vendorFilter.isNotEmpty ||
        vm.filter.conflictsOnly ||
        vm.filter.selectedStatuses.isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isScanning ? Icons.radar : Icons.lan_outlined,
            size: 54,
            color: isScanning
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isScanning
                ? 'Sweeping Subnet ${vm.scanProgress.targetSubnet}...'
                : (hasActiveFilter
                      ? 'No hosts match your active search filters'
                      : 'No ARP or Subnet Discovery Data Loaded'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isScanning
                ? 'Emitting concurrent ICMP echo sweeps & reading OS ARP tables...'
                : (hasActiveFilter
                      ? 'Try clearing your search query or status filter chips'
                      : 'Select a network interface above and click "Sweep Subnet", or read your local ARP cache.'),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          if (hasActiveFilter)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.filter_alt_off, size: 16),
              label: const Text('Reset All Filters'),
              onPressed: () => vm.resetFilters(),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Sweep Subnet'),
                  onPressed: isScanning ? null : () => vm.startSubnetScan(),
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.bolt, size: 16),
                  label: const Text('Read Local ARP Cache'),
                  onPressed: isScanning
                      ? null
                      : () => vm.startSubnetScan(arpCacheOnly: true),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Load Demo Subnet (with Conflicts)'),
                  onPressed: () => vm.loadDemoTopology(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(
    BuildContext context,
    ArpScoutViewModel vm,
    Map<ArpTableColumn, double> widths,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
      child: Row(
        children: ArpTableColumn.values.map((col) {
          return _buildHeaderCell(context, vm, col, widths[col]!);
        }).toList(),
      ),
    );
  }

  Widget _buildHeaderCell(
    BuildContext context,
    ArpScoutViewModel vm,
    ArpTableColumn col,
    double width,
  ) {
    final isSorted = vm.sortColumn == col.sortKey;
    final isAsc = vm.sortAscending;

    return SizedBox(
      width: width,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => vm.setSort(col.sortKey),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        col.label,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isSorted
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSorted) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isAsc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  final newWidth = max(
                    col.minWidth,
                    (_columnWidths[col] ?? col.defaultWidth) + details.delta.dx,
                  );
                  _columnWidths[col] = newWidth;
                });
              },
              child: Container(
                width: 12,
                height: 24,
                alignment: Alignment.center,
                child: Container(
                  width: 1.5,
                  height: 14,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    ArpScoutViewModel vm,
    ArpHostRecord record,
    Map<ArpTableColumn, double> widths,
  ) {
    final isSelected = vm.selectedRecord?.ipAddress == record.ipAddress;

    Color rowBackground = Colors.transparent;
    if (isSelected) {
      rowBackground = Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.15);
    } else if (record.hasConflict) {
      rowBackground = const Color(0xFFEF4444).withValues(alpha: 0.08);
    } else if (record.associatedIps.length > 1) {
      rowBackground = const Color(0xFFF59E0B).withValues(alpha: 0.05);
    }

    return InkWell(
      onTap: () => vm.selectRecord(record),
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, vm, record, details.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: rowBackground,
        child: Row(
          children: [
            // 1. Status Badge
            SizedBox(
              width: widths[ArpTableColumn.status],
              child: _buildStatusBadge(record.status),
            ),

            // 2. IPv4 Address (Monospace)
            SizedBox(
              width: widths[ArpTableColumn.ip],
              child: Text(
                record.ipAddress,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: record.hasConflict
                      ? const Color(0xFFFCA5A5)
                      : Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 3. MAC Address (Monospace + conflict indicator)
            SizedBox(
              width: widths[ArpTableColumn.mac],
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      record.macAddress,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: record.hasConflict
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF38BDF8),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (record.conflictingMacs.length > 1) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFEF4444)),
                      ),
                      child: Text(
                        '+${record.conflictingMacs.length - 1}',
                        style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 4. OUI Hardware Vendor
            SizedBox(
              width: widths[ArpTableColumn.vendor],
              child: Text(
                record.vendor,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 5. Device Name / Hostname (Prominent Shared Suite Device Name)
            SizedBox(
              width: widths[ArpTableColumn.hostname],
              child: InkWell(
                onTap: () => _showEditDeviceNameDialog(context, vm, record),
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        record.displayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: record.customName != null
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: record.customName != null
                              ? const Color(0xFF38BDF8)
                              : (record.hostname != null
                                  ? Colors.white
                                  : Colors.grey),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.edit_outlined,
                      size: 11,
                      color: Colors.grey.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            ),

            // 6. RTT Latency (Monospace)
            SizedBox(
              width: widths[ArpTableColumn.rtt],
              child: Text(
                record.rttMs != null
                    ? '${record.rttMs!.toStringAsFixed(2)} ms'
                    : '-',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: _rttColor(record.rttMs),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 7. TTL / OS Hint
            SizedBox(
              width: widths[ArpTableColumn.ttl],
              child: Text(
                record.osHintFromTtl,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 8. Discovery Method
            SizedBox(
              width: widths[ArpTableColumn.discovery],
              child: Text(
                record.discoveryMethod,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 9. Last Seen Timestamp (Monospace)
            SizedBox(
              width: widths[ArpTableColumn.lastSeen],
              child: Text(
                _timeFormatter.format(record.lastSeen),
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // 10. Notes / Conflict Details
            SizedBox(
              width: widths[ArpTableColumn.notes],
              child: Text(
                record.notes.isNotEmpty
                    ? record.notes
                    : (record.associatedIps.length > 1
                          ? 'Multi-Homed MAC also seen on: ${record.associatedIps.join(", ")}'
                          : '${record.interfaceName} • ${record.arpType} ARP'),
                style: TextStyle(
                  fontSize: 12,
                  color: record.hasConflict
                      ? const Color(0xFFFCA5A5)
                      : Colors.white70,
                  fontWeight: record.hasConflict
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _rttColor(double? rtt) {
    if (rtt == null) return Colors.grey;
    if (rtt < 2.5) return const Color(0xFF10B981);
    if (rtt < 10.0) return const Color(0xFF38BDF8);
    return const Color(0xFFF59E0B);
  }

  /// Canonical Status Badge from Section 5.1 of UI_AND_DESIGN_PRINCIPLES.md
  Widget _buildStatusBadge(HostStatus status) {
    final statusColor = status.color;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(status.icon, size: 12, color: statusColor),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                status.label.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingMoreIndicator(
    BuildContext context,
    ArpScoutViewModel vm,
    int currentCount,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading more hosts... ($currentCount of ${vm.totalHostCount} loaded)',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(
    BuildContext context,
    ArpScoutViewModel vm,
    int loadedCount,
  ) {
    final conflictCount = vm.conflictCount;
    final lastScan = vm.scanProgress.lastScanCompletedAt;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(
            Icons.storage_outlined,
            size: 14,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            'Showing $loadedCount of ${vm.totalHostCount} matching hosts (${vm.unfilteredTotalCount} total in SQLite)',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          if (conflictCount > 0) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                '• $conflictCount IP ${conflictCount == 1 ? "CONFLICT" : "CONFLICTS"}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEF4444),
                ),
              ),
            ),
          ],
          if (lastScan != null) ...[
            const SizedBox(width: 12),
            Text(
              '• Last Sweep: ${_timeFormatter.format(lastScan)}',
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Colors.grey,
              ),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              vm.scanProgress.currentPhase,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _showContextMenu(
    BuildContext context,
    ArpScoutViewModel vm,
    ArpHostRecord record,
    Offset position,
  ) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final ouiPrefix = record.macAddress.length >= 8
        ? record.macAddress.substring(0, 8)
        : record.macAddress;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      items: [
        PopupMenuItem(
          value: 'edit_name',
          child: Row(
            children: [
              const Icon(Icons.edit_note, size: 16, color: Color(0xFF38BDF8)),
              const SizedBox(width: 8),
              Text('Edit Device Name (${record.displayName})...'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'copy_ip',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 15),
              const SizedBox(width: 8),
              Text('Copy IP (${record.ipAddress})'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_mac',
          child: Row(
            children: [
              const Icon(Icons.memory, size: 15),
              const SizedBox(width: 8),
              Text('Copy MAC (${record.macAddress})'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_vendor',
          child: Row(
            children: [
              const Icon(Icons.business, size: 15),
              const SizedBox(width: 8),
              Text('Copy Vendor (${record.vendor})'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'filter_mac',
          child: Row(
            children: [
              const Icon(Icons.filter_alt, size: 15),
              const SizedBox(width: 8),
              Text('Search by MAC: ${record.macAddress}'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'filter_oui',
          child: Row(
            children: [
              const Icon(Icons.filter_alt_outlined, size: 15),
              const SizedBox(width: 8),
              Text('Filter by OUI Prefix: $ouiPrefix'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'filter_vendor',
          child: Row(
            children: [
              const Icon(Icons.domain, size: 15),
              const SizedBox(width: 8),
              Text('Filter by Vendor: ${record.vendor}'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'reprobe',
          child: Row(
            children: [
              Icon(Icons.radar, size: 15, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text('Re-probe Host (ICMP + ARP)'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'simulate_conflict',
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 15,
                color: Color(0xFFF59E0B),
              ),
              SizedBox(width: 8),
              Text('Simulate Gratuitous ARP Conflict on this IP'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!context.mounted || value == null) return;
      switch (value) {
        case 'edit_name':
          _showEditDeviceNameDialog(context, vm, record);
          break;
        case 'copy_ip':
          Clipboard.setData(ClipboardData(text: record.ipAddress));
          break;
        case 'copy_mac':
          Clipboard.setData(ClipboardData(text: record.macAddress));
          break;
        case 'copy_vendor':
          Clipboard.setData(ClipboardData(text: record.vendor));
          break;
        case 'filter_mac':
          vm.setMacFilter(record.macAddress);
          break;
        case 'filter_oui':
          vm.setMacFilter(ouiPrefix);
          break;
        case 'filter_vendor':
          vm.setVendorFilter(record.vendor);
          break;
        case 'reprobe':
          vm.reprobeSingleHost(record);
          break;
        case 'simulate_conflict':
          vm.simulateRogueMacConflict(target: record);
          break;
      }
    });
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
