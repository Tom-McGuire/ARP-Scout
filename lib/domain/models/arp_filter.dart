import 'host_status.dart';

class ArpFilterCriteria {
  const ArpFilterCriteria({
    this.searchQuery = '',
    this.ipFilter = '',
    this.macFilter = '',
    this.vendorFilter = '',
    this.selectedStatuses = const {},
    this.conflictsOnly = false,
    this.sortColumn = 'ip_numeric',
    this.sortAscending = true,
  });

  final String searchQuery;
  final String ipFilter;
  final String macFilter;
  final String vendorFilter;
  final Set<HostStatus> selectedStatuses;
  final bool conflictsOnly;
  final String sortColumn;
  final bool sortAscending;

  bool get hasActiveFilter =>
      searchQuery.trim().isNotEmpty ||
      ipFilter.trim().isNotEmpty ||
      macFilter.trim().isNotEmpty ||
      vendorFilter.trim().isNotEmpty ||
      conflictsOnly ||
      (selectedStatuses.isNotEmpty &&
          selectedStatuses.length < HostStatus.values.length);

  ArpFilterCriteria copyWith({
    String? searchQuery,
    String? ipFilter,
    String? macFilter,
    String? vendorFilter,
    Set<HostStatus>? selectedStatuses,
    bool? conflictsOnly,
    String? sortColumn,
    bool? sortAscending,
  }) {
    return ArpFilterCriteria(
      searchQuery: searchQuery ?? this.searchQuery,
      ipFilter: ipFilter ?? this.ipFilter,
      macFilter: macFilter ?? this.macFilter,
      vendorFilter: vendorFilter ?? this.vendorFilter,
      selectedStatuses: selectedStatuses ?? this.selectedStatuses,
      conflictsOnly: conflictsOnly ?? this.conflictsOnly,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}
