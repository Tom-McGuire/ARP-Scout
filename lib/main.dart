import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'data/services/ipc/app_launch_arguments.dart';
import 'data/services/ipc/inter_app_ipc_service.dart';
import 'ui/features/scout/view_models/arp_scout_view_model.dart';
import 'ui/features/scout/views/arp_scout_screen.dart';
import 'ui/theme/app_theme.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SharedDeviceDatabase.instance.init();
  } catch (e) {
    debugPrint('Shared database offline: $e');
  }

  // Parse cold-start CLI args
  final cliArgs = AppLaunchArguments.parse(args);

  final viewModel = ArpScoutViewModel(
    initialSubnet: cliArgs.subnet,
    initialAdapterIp: cliArgs.adapterIp,
    initialAdapterName: cliArgs.adapterName,
    autoStart: cliArgs.autoStart,
  );

  // Single instance / IPC loopback listener initialization on port 44102
  await InterAppIpcService.startListener(
    port: InterAppIpcService.arpScoutIpcPort,
    onCommand: (payload) {
      viewModel.handleIncomingCommand(
        subnet: payload['subnet'] as String?,
        adapterIp: payload['adapterIp'] as String?,
        adapterName: payload['adapterName'] as String?,
        autoStart: payload['autoStart'] == true,
      );
    },
  );

  runApp(ArpScoutApp(viewModel: viewModel));
}

class ArpScoutApp extends StatelessWidget {
  const ArpScoutApp({
    super.key,
    this.viewModel,
    this.initialSubnet,
    this.initialAdapterIp,
    this.initialAdapterName,
    this.autoStart = false,
  });

  final ArpScoutViewModel? viewModel;
  final String? initialSubnet;
  final String? initialAdapterIp;
  final String? initialAdapterName;
  final bool autoStart;

  @override
  Widget build(BuildContext context) {
    final effectiveVm = viewModel;
    final app = MaterialApp(
      title: 'ARP & Subnet Scout',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      home: const ArpScoutScreen(),
    );

    if (effectiveVm != null) {
      return ChangeNotifierProvider<ArpScoutViewModel>.value(
        value: effectiveVm,
        child: app,
      );
    }

    return ChangeNotifierProvider<ArpScoutViewModel>(
      create: (_) => ArpScoutViewModel(
        initialSubnet: initialSubnet,
        initialAdapterIp: initialAdapterIp,
        initialAdapterName: initialAdapterName,
        autoStart: autoStart,
      ),
      child: app,
    );
  }
}
