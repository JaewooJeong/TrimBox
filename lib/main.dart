import 'package:flutter/material.dart';

import 'screens/simulator_screen.dart';

void main() {
  runApp(const TrimBoxApp());
}

class TrimBoxApp extends StatelessWidget {
  const TrimBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TrimBox Simulator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1C1C1C),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4DA3FF),
          surface: Color(0xFF252525),
          error: Color(0xFFFF4D4D),
        ),
        fontFamily: 'NotoSansKR',
      ),
      home: const SimulatorScreen(),
    );
  }
}
