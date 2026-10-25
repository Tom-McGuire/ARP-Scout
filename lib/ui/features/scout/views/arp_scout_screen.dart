import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/arp_scout_view_model.dart';
import 'arp_control_bar.dart';
import 'arp_detail_panel.dart';
import 'arp_filter_bar.dart';
import 'arp_table_view.dart';

class ArpScoutScreen extends StatefulWidget {
  const ArpScoutScreen({super.key});

  @override
  State<ArpScoutScreen> createState() => _ArpScoutScreenState();
}

class _ArpScoutScreenState extends State<ArpScoutScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    final vm = Provider.of<ArpScoutViewModel>(context, listen: false);
    if (vm.isScanningOrWatching) {
      await vm.stopAllServices();
    }
    return AppExitResponse.exit;
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = context.select<ArpScoutViewModel, bool>(
      (vm) => vm.selectedRecord != null,
    );

    return Scaffold(
      body: Column(
        children: [
          // Tier 1 & 2: Top Control Bar + Conditional Scan/Conflict Alert Banner
          const ArpControlBar(),

          // Tier 3: Dense Filter & Triage Toolbar (Search, IP, MAC/OUI, Vendor, Status Chips)
          const ArpFilterBar(),

          // Tier 4: Primary Data Workspace (Virtualized High-Density ARP Table)
          const Expanded(
            child: ArpTableView(),
          ),

          // Tier 5: Collapsible Bottom Detail Inspector
          if (hasSelection) const ArpDetailPanel(),
        ],
      ),
    );
  }
}
