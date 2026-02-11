import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/stopwatch_provider.dart';
import 'screens/home_screen.dart';
import 'overlay/overlay_entry.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(MyApp(prefs: prefs));
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const OverlayApp());
}

class MyApp extends StatelessWidget {
  final SharedPreferences prefs;

  const MyApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => StopwatchProvider(prefs),
        ),
      ],
      child: Consumer<StopwatchProvider>(
        builder: (context, provider, _) {
          return MaterialApp(
            title: 'Cronômetro',
            themeMode: provider.themeMode,
            theme: ThemeData(
              colorSchemeSeed: Colors.blue,
              useMaterial3: true,
              brightness: Brightness.light,
            ),
            darkTheme: ThemeData(
              colorSchemeSeed: Colors.blue,
              useMaterial3: true,
              brightness: Brightness.dark,
            ),
            home: const HomeScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
