import 'dart:io';
import '../../../domain/models/network_adapter_info.dart';

class NetworkAdapterService {
  static Future<List<NetworkAdapterInfo>> getAvailableAdapters() async {
    final adapters = <NetworkAdapterInfo>[];

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 &&
              !addr.isLoopback &&
              !addr.address.startsWith('169.254.')) {
            adapters.add(
              NetworkAdapterInfo(
                name: interface.name,
                ipAddress: addr.address,
                subnetCidr:
                    NetworkAdapterInfo.inferDefaultSubnetCidr(addr.address),
              ),
            );
          }
        }
      }
    } catch (_) {
      // Ignore platform interface enumeration errors and fall back cleanly
    }

    // Always include the global ARP Cache option
    adapters.add(NetworkAdapterInfo.all);

    return adapters;
  }
}
