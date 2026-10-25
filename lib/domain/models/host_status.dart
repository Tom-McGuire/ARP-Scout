import 'package:flutter/material.dart';

enum HostStatus {
  conflict(
    code: 0,
    label: 'IP CONFLICT',
    description: 'Multiple MAC addresses claiming the same IP address',
    color: Color(0xFFEF4444),
    icon: Icons.warning_amber_rounded,
  ),
  online(
    code: 1,
    label: 'ONLINE',
    description: 'Responded to both L2 ARP and L3 ICMP probes',
    color: Color(0xFF10B981),
    icon: Icons.check_circle_outline,
  ),
  arpOnly(
    code: 2,
    label: 'ARP ONLY',
    description: 'Present in L2 ARP cache (ICMP blocked/firewalled)',
    color: Color(0xFF38BDF8),
    icon: Icons.lan_outlined,
  ),
  icmpOnly(
    code: 3,
    label: 'ICMP ONLY',
    description: 'Responded to L3 ping (routed or local interface)',
    color: Color(0xFFF59E0B),
    icon: Icons.router_outlined,
  ),
  stale(
    code: 4,
    label: 'STALE',
    description: 'Previously discovered, no response in latest sweep',
    color: Color(0xFF9CA3AF),
    icon: Icons.history,
  );

  const HostStatus({
    required this.code,
    required this.label,
    required this.description,
    required this.color,
    required this.icon,
  });

  final int code;
  final String label;
  final String description;
  final Color color;
  final IconData icon;

  static HostStatus fromCode(int code) {
    return HostStatus.values.firstWhere(
      (s) => s.code == code,
      orElse: () => HostStatus.online,
    );
  }
}
