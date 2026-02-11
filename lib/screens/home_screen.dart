import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../providers/stopwatch_provider.dart';
import '../widgets/stopwatch_display.dart';
import '../widgets/lap_list.dart';
import '../widgets/control_buttons.dart';
import '../widgets/settings_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late Timer _timer;
  late Future<PackageInfo> _packageInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _packageInfo = PackageInfo.fromPlatform();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      final provider = context.read<StopwatchProvider>();
      provider.tick();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final provider = context.read<StopwatchProvider>();
      provider.syncOverlayState();
    }
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final provider = context.read<StopwatchProvider>();
      provider.persistCurrentSessionSnapshot(updateEnd: provider.isRunning);
    }
    if (state == AppLifecycleState.detached) {
      final provider = context.read<StopwatchProvider>();
      provider.shutdownOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cronômetro'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: () async {
              final provider = context.read<StopwatchProvider>();
              if (!provider.showOverlay) {
                await provider.toggleOverlay();
              }
            },
            tooltip: 'Modo flutuante',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (context) => const SettingsPanel(),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const Expanded(
            child: StopwatchDisplay(),
          ),
          const LapList(),
          const SizedBox(height: 20),
          const ControlButtons(),
          const SizedBox(height: 8),
          FutureBuilder<PackageInfo>(
            future: _packageInfo,
            builder: (context, snapshot) {
              final info = snapshot.data;
              final versionLabel = info == null ? 'v--' : 'v${info.version}';
              return Text(
                '$versionLabel • Desenvolvido por KN',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
