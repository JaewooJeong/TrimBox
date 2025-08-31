import 'package:flutter/material.dart';
import 'screens/trunk_simulator_screen.dart';

void main() {
  runApp(const TrimBoxApp());
}

class TrimBoxApp extends StatelessWidget {
  const TrimBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrimBox Simulator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4DA3FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const TrunkSimulatorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
