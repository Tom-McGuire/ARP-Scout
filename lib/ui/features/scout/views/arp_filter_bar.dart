import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/host_status.dart';
import '../view_models/arp_scout_view_model.dart';

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
          Wrap(
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
                  avatar: Icon(
                    status.icon,
                    size: 13,
                    color: status.color,
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
          ),
        ],
      ),
    );
  }
}
