import 'package:flutter/material.dart';

import '../../../../domain/models/arp_host_record.dart';

const Color stpRootColor = Color(0xFFF59E0B);
const Color igmpQuerierColor = Color(0xFF14B8A6);

/// Inline role pills (`STP ROOT`, `IGMP QUERIER`) for a host record.
class L2RolePills extends StatelessWidget {
  const L2RolePills({super.key, required this.record});

  final ArpHostRecord record;

  @override
  Widget build(BuildContext context) {
    if (!record.isStpRootBridge && !record.isIgmpQuerier) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (record.isStpRootBridge) _pill('👑 STP ROOT', stpRootColor),
        if (record.isIgmpQuerier) _pill('📡 IGMP QUERIER', igmpQuerierColor),
      ],
    );
  }

  Widget _pill(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// Banner shown when STP Root and IGMP Querier are on different switches.
class L2RoleMisalignmentBanner extends StatelessWidget {
  const L2RoleMisalignmentBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: stpRootColor.withValues(alpha: 0.15),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: stpRootColor),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'STP Root Bridge and IGMP Querier are elected on different switches.',
              style: TextStyle(fontSize: 11, color: stpRootColor),
            ),
          ),
        ],
      ),
    );
  }
}
