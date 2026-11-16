import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';

import 'data/services/ipc/app_launch_arguments.dart';
import 'data/services/ipc/inter_app_ipc_service.dart';
import 'data/services/storage/suite_theme_sync_service.dart';
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

  final initialMode = await SuiteThemeSyncService.getThemeMode();
  AppTheme.isDark = (initialMode == 'dark');

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

class ArpScoutApp extends StatefulWidget {
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
  State<ArpScoutApp> createState() => _ArpScoutAppState();
}

class _ArpScoutAppState extends State<ArpScoutApp> {
  StreamSubscription<void>? _dbSub;
  String _themeMode = AppTheme.isDark ? 'dark' : 'light';

  @override
  void initState() {
    super.initState();
    _syncTheme();
    _dbSub = SharedDeviceDatabase.instance.onDatabaseChanged.listen((_) {
      _syncTheme();
    });
  }

  Future<void> _syncTheme() async {
    final mode = await SuiteThemeSyncService.getThemeMode();
    if (mounted && mode != _themeMode) {
      setState(() {
        _themeMode = mode;
        AppTheme.isDark = (mode == 'dark');
      });
    }
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveVm = widget.viewModel;
    final app = MaterialApp(
      title: 'ARP & Subnet Scout',
      debugShowCheckedModeBanner: false,
      themeMode: AppTheme.isDark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: KeyedSubtree(
        key: ValueKey(_themeMode),
        child: const ArpScoutScreen(),
      ),
    );

    if (effectiveVm != null) {
      return ChangeNotifierProvider<ArpScoutViewModel>.value(
        value: effectiveVm,
        child: app,
      );
    }

    return ChangeNotifierProvider<ArpScoutViewModel>(
      create: (_) => ArpScoutViewModel(
        initialSubnet: widget.initialSubnet,
        initialAdapterIp: widget.initialAdapterIp,
        initialAdapterName: widget.initialAdapterName,
        autoStart: widget.autoStart,
      ),
      child: app,
    );
  }
}
