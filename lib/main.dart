import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ui/features/scout/view_models/arp_scout_view_model.dart';
import 'ui/features/scout/views/arp_scout_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ArpScoutApp());
}

class ArpScoutApp extends StatelessWidget {
  const ArpScoutApp({super.key, this.viewModel});

  final ArpScoutViewModel? viewModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ArpScoutViewModel>(
      create: (_) => viewModel ?? ArpScoutViewModel(),
      child: MaterialApp(
        title: 'ARP & Subnet Scout',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme(),
        home: const ArpScoutScreen(),
      ),
    );
  }
}
