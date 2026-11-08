import 'dart:async';
import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/arp_filter.dart';
import '../../../../domain/models/arp_host_record.dart';
import '../../../../domain/models/host_status.dart';
import '../view_models/arp_scout_view_model.dart';
import 'dialogs/device_library_dialog.dart';
import 'dialogs/edit_device_dialog.dart';

class ArpFilterBar extends StatefulWidget {
  const ArpFilterBar({super.key});

  @override
  State<ArpFilterBar> createState() => _ArpFilterBarState();
}

class _ArpFilterBarState extends State<ArpFilterBar> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _macController = TextEditingController();
  final TextEditingController _vendorController = TextEditingController();

  Timer? _searchDebounce;
  Timer? _ipDebounce;
  Timer? _macDebounce;
  Timer? _vendorDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _ipDebounce?.cancel();
    _macDebounce?.cancel();
    _vendorDebounce?.cancel();
    _searchController.dispose();
    _ipController.dispose();
    _macController.dispose();
    _vendorController.dispose();
    super.dispose();
  }

  void _syncControllersWithFilter(ArpScoutViewModel vm) {
    final f = vm.filter;
    if (_searchController.text != f.searchQuery &&
        !(_searchDebounce?.isActive ?? false)) {
      _searchController.text = f.searchQuery;
    }
    if (_ipController.text != f.ipFilter && !(_ipDebounce?.isActive ?? false)) {
      _ipController.text = f.ipFilter;
    }
    if (_macController.text != f.macFilter &&
        !(_macDebounce?.isActive ?? false)) {
      _macController.text = f.macFilter;
    }
    if (_vendorController.text != f.vendorFilter &&
        !(_vendorDebounce?.isActive ?? false)) {
      _vendorController.text = f.vendorFilter;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ArpScoutViewModel>();
    final filter = vm.filter;
    final statusCounts = vm.statusCounts;
    final deviceCounts = vm.deviceCounts;

    _syncControllersWithFilter(vm);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Quick Search + Dedicated IP Address Search + Dedicated MAC Address Search + Vendor Filter
          Row(
            children: [
              // 1. Unified Search Input
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {});
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 180),
                        () => vm.setSearchQuery(val),
                      );
                    },
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search any IP, MAC, vendor, hostname...',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _searchDebounce?.cancel();
                                _searchController.clear();
                                vm.setSearchQuery('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 2. Dedicated IP Address Filter (Monospace)
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _ipController,
                    onChanged: (val) {
                      setState(() {});
                      _ipDebounce?.cancel();
                      _ipDebounce = Timer(
                        const Duration(milliseconds: 180),
                        () => vm.setIpFilter(val),
                      );
                    },
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search IP (e.g. 192.168.10.50)...',
                      prefixIcon: const Icon(Icons.lan_outlined, size: 15),
                      suffixIcon: _ipController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _ipDebounce?.cancel();
                                _ipController.clear();
                                vm.setIpFilter('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 3. Dedicated MAC Address / OUI Filter (Monospace)
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _macController,
                    onChanged: (val) {
                      setState(() {});
                      _macDebounce?.cancel();
                      _macDebounce = Timer(
                        const Duration(milliseconds: 180),
                        () => vm.setMacFilter(val),
                      );
                    },
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search MAC / OUI (e.g. 00:50:56)...',
                      prefixIcon: const Icon(Icons.memory, size: 16),
                      suffixIcon: _macController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _macDebounce?.cancel();
                                _macController.clear();
                                vm.setMacFilter('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 4. Dedicated Vendor Filter
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _vendorController,
                    onChanged: (val) {
                      setState(() {});
                      _vendorDebounce?.cancel();
                      _vendorDebounce = Timer(
                        const Duration(milliseconds: 180),
                        () => vm.setVendorFilter(val),
                      );
                    },
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Filter Vendor (Cisco, Ubiquiti)...',
                      prefixIcon: const Icon(
                        Icons.business_outlined,
                        size: 15,
                      ),
                      suffixIcon: _vendorController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _vendorDebounce?.cancel();
                                _vendorController.clear();
                                vm.setVendorFilter('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Auto-Detected Switch
              _buildAutoDetectedSwitch(context, vm),

              if (filter.hasActiveFilter) ...[
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _ipDebounce?.cancel();
                    _macDebounce?.cancel();
                    _vendorDebounce?.cancel();
                    _searchController.clear();
                    _ipController.clear();
                    _macController.clear();
                    _vendorController.clear();
                    vm.resetFilters();
                  },
                  icon: const Icon(Icons.filter_alt_off, size: 15),
                  label: const Text(
                    'Clear All Filters',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Status & Conflict Triage Chips
          _buildStatusTriageRow(context, vm, filter, statusCounts),

          const SizedBox(height: 8),

          // Row 3: Devices Quick-Filter Row
          _buildDevicesRow(context, vm, filter, deviceCounts),
        ],
      ),
    );
  }

  Widget _buildStatusTriageRow(
    BuildContext context,
    ArpScoutViewModel vm,
    ArpFilterCriteria filter,
    Map<HostStatus, int> statusCounts,
  ) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'STATUS TRIAGE:',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 4),
        ...HostStatus.values.map((status) {
          final isSelected = filter.selectedStatuses.contains(status);
          final count = statusCounts[status] ?? 0;

          return FilterChip(
            selected: isSelected,
            showCheckmark: false,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            avatar: CircleAvatar(
              radius: 5,
              backgroundColor: status.color,
            ),
            label: Text(
              '${status.label} ($count)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ||
                        (status == HostStatus.conflict && count > 0)
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: isSelected
                    ? Colors.white
                    : (status == HostStatus.conflict && count > 0
                          ? const Color(0xFFFCA5A5)
                          : Colors.grey.shade400),
              ),
            ),
            selectedColor: status.color.withValues(alpha: 0.35),
            backgroundColor: const Color(0xFF252526),
            side: BorderSide(
              color: isSelected
                  ? status.color
                  : (status == HostStatus.conflict && count > 0
                        ? status.color.withValues(alpha: 0.6)
                        : const Color(0xFF3E3E42)),
              width: 1,
            ),
            onSelected: (_) => vm.toggleStatus(status),
          );
        }),
      ],
    );
  }

  Widget _buildDevicesRow(
    BuildContext context,
    ArpScoutViewModel vm,
    ArpFilterCriteria filter,
    Map<String, int> deviceCounts,
  ) {
    final visibleShared = vm.visibleSharedDevices;
    final autoDetected = vm.autoDetectedUnlabeledHosts;
    final selectedMacs = filter.selectedDeviceMacs;

    return Row(
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.devices, size: 14, color: Colors.blueAccent),
              SizedBox(width: 4),
              Text(
                'DEVICES:',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 1. Shared Library Devices
                ...visibleShared.map((device) {
                  final normMac = SharedDevice.normalizeMac(device.macAddress);
                  final isSelected = selectedMacs.contains(normMac);
                  final count = deviceCounts[normMac] ?? 0;
                  final catColor = _getCategoryColor(device.deviceType);

                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: GestureDetector(
                      onSecondaryTapDown: (details) =>
                          _showDeviceMenu(context, details, device, vm),
                      child: FilterChip(
                        selected: isSelected,
                        showCheckmark: false,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        avatar: CircleAvatar(
                          radius: 5,
                          backgroundColor: catColor,
                        ),
                        label: Text(
                          '${device.name} ($count)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.grey.shade400,
                          ),
                        ),
                        selectedColor: catColor.withValues(alpha: 0.35),
                        backgroundColor: const Color(0xFF252526),
                        side: BorderSide(
                          color: isSelected ? catColor : const Color(0xFF3E3E42),
                          width: 1,
                        ),
                        onSelected: (_) => vm.toggleDevicePill(device.macAddress),
                        tooltip: 'MAC: ${device.macAddress}\nRight-click for options',
                      ),
                    ),
                  );
                }),

                if (vm.showAutoDetected && autoDetected.isNotEmpty) ...[
                  if (visibleShared.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      height: 18,
                      width: 1,
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // 2. Auto-Detected Unlabeled Hosts
                  ...autoDetected.map((host) {
                    final normMac = SharedDevice.normalizeMac(host.macAddress);
                    final isSelected = selectedMacs.contains(normMac);
                    final count = deviceCounts[normMac] ?? 0;
                    final displayName = (host.hostname != null && host.hostname!.trim().isNotEmpty)
                        ? host.hostname!.trim()
                        : host.ipAddress;

                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: GestureDetector(
                        onSecondaryTapDown: (details) =>
                            _showAutoDetectedDeviceMenu(context, details, host, vm),
                        child: FilterChip(
                          selected: isSelected,
                          showCheckmark: false,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          avatar: const CircleAvatar(
                            radius: 5,
                            backgroundColor: Colors.grey,
                          ),
                          label: Text(
                            '$displayName ($count)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : Colors.grey.shade400,
                            ),
                          ),
                          selectedColor: Colors.blueAccent.withValues(alpha: 0.35),
                          backgroundColor: const Color(0xFF252526),
                          side: BorderSide(
                            color: isSelected ? Colors.blueAccent : const Color(0xFF3E3E42),
                            width: 1,
                          ),
                          onSelected: (_) => vm.toggleDevicePill(host.macAddress),
                          tooltip: 'Auto-detected host (${host.macAddress})\nRight-click to label or hide',
                        ),
                      ),
                    );
                  }),
                ],

                // 3. Manage ActionChip
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ActionChip(
                    avatar: const Icon(Icons.settings_outlined, size: 13),
                    label: const Text('Manage', style: TextStyle(fontSize: 11)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: const Color(0xFF252526),
                    side: const BorderSide(color: Color(0xFF3E3E42), width: 1),
                    tooltip: 'Manage device library and visibility in ARP Scout',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => ChangeNotifierProvider.value(
                          value: vm,
                          child: const DeviceLibraryDialog(),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAutoDetectedSwitch(BuildContext context, ArpScoutViewModel vm) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: vm.showAutoDetected
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : const Color(0xFF252526),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: vm.showAutoDetected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
              : const Color(0xFF3E3E42),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sensors,
            size: 14,
            color: vm.showAutoDetected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
          ),
          const SizedBox(width: 6),
          const Text(
            'Auto-Detected',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 20,
            width: 32,
            child: FittedBox(
              fit: BoxFit.contain,
              child: Switch(
                value: vm.showAutoDetected,
                onChanged: (val) => vm.setShowAutoDetected(val),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String? deviceType) {
    final cat = DeviceCategory.fromKey(deviceType);
    switch (cat) {
      case DeviceCategory.pc:
      case DeviceCategory.laptop:
        return Colors.blueAccent;
      case DeviceCategory.server:
        return Colors.purpleAccent;
      case DeviceCategory.router:
        return Colors.cyanAccent;
      case DeviceCategory.switchDevice:
        return Colors.tealAccent;
      case DeviceCategory.accessPoint:
        return Colors.lightBlueAccent;
      case DeviceCategory.mobile:
        return Colors.greenAccent;
      case DeviceCategory.printer:
        return Colors.orangeAccent;
      case DeviceCategory.nas:
        return Colors.amberAccent;
      case DeviceCategory.iot:
        return Colors.yellowAccent;
      case DeviceCategory.camera:
        return Colors.pinkAccent;
      case DeviceCategory.other:
        return Colors.blueGrey;
    }
  }

  Future<void> _showDeviceMenu(
    BuildContext context,
    TapDownDetails details,
    SharedDevice device,
    ArpScoutViewModel vm,
  ) async {
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(40, 40),
      Offset.zero & MediaQuery.of(context).size,
    );

    final value = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 16),
              const SizedBox(width: 8),
              Text('Edit "${device.name}"'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'hide',
          child: const Row(
            children: [
              Icon(Icons.visibility_off_outlined, size: 16),
              SizedBox(width: 8),
              Text('Hide in ARP Scout'),
            ],
          ),
        ),
      ],
    );

    if (!context.mounted) return;

    if (value == 'edit') {
      showDialog(
        context: context,
        builder: (ctx) => EditDeviceDialog(
          macAddress: device.macAddress,
          initialName: device.name,
          initialCategory: device.deviceType,
          initialVendor: device.vendor,
          initialNotes: device.notes,
          onSave: ({
            required String mac,
            required String name,
            String? category,
            String? vendor,
            String? notes,
          }) {
            vm.updateDeviceMetadata(
              mac: mac,
              name: name,
              category: category,
              vendor: vendor,
              notes: notes,
            );
          },
        ),
      );
    } else if (value == 'hide') {
      vm.toggleDeviceVisibility(device.macAddress);
    }
  }

  Future<void> _showAutoDetectedDeviceMenu(
    BuildContext context,
    TapDownDetails details,
    ArpHostRecord host,
    ArpScoutViewModel vm,
  ) async {
    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(40, 40),
      Offset.zero & MediaQuery.of(context).size,
    );

    final value = await showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'label',
          child: Row(
            children: [
              const Icon(Icons.label_outline, size: 16),
              const SizedBox(width: 8),
              Text('Label / Add to Library (${host.macAddress})'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'hide',
          child: const Row(
            children: [
              Icon(Icons.visibility_off_outlined, size: 16),
              SizedBox(width: 8),
              Text('Hide in ARP Scout'),
            ],
          ),
        ),
      ],
    );

    if (!context.mounted) return;

    if (value == 'label') {
      showDialog(
        context: context,
        builder: (ctx) => EditDeviceDialog(
          macAddress: host.macAddress,
          initialName: (host.hostname != null && host.hostname!.trim().isNotEmpty)
              ? host.hostname!.trim()
              : host.ipAddress,
          initialCategory: 'other',
          initialVendor: host.vendor,
          onSave: ({
            required String mac,
            required String name,
            String? category,
            String? vendor,
            String? notes,
          }) {
            vm.updateDeviceMetadata(
              mac: mac,
              name: name,
              category: category,
              vendor: vendor,
              notes: notes,
            );
          },
        ),
      );
    } else if (value == 'hide') {
      vm.toggleDeviceVisibility(host.macAddress);
    }
  }
}
