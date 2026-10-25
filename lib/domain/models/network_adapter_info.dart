class NetworkAdapterInfo {
  const NetworkAdapterInfo({
    required this.name,
    required this.ipAddress,
    this.subnetCidr = '192.168.1.0/24',
  });

  final String name;
  final String ipAddress;
  final String subnetCidr;

  static const NetworkAdapterInfo all = NetworkAdapterInfo(
    name: 'All Interfaces (ARP Cache)',
    ipAddress: '0.0.0.0',
    subnetCidr: '192.168.1.0/24',
  );

  bool get isAllInterfaces => ipAddress == '0.0.0.0';

  String get displayName =>
      isAllInterfaces ? name : '$name ($ipAddress)';

  static String inferDefaultSubnetCidr(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length == 4 && ip != '0.0.0.0' && ip != '127.0.0.1') {
      return '${parts[0]}.${parts[1]}.${parts[2]}.0/24';
    }
    return '192.168.1.0/24';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkAdapterInfo &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          ipAddress == other.ipAddress;

  @override
  int get hashCode => Object.hash(name, ipAddress);
}
