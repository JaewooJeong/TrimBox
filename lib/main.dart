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
        // M3 ElevatedButton 은 전경색 기본값이 primary 라서 primary 배경 위에 글자가
        // 사라진다. 흰 글자로 고정.
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: const Color(0xFF4DA3FF),
          ),
        ),
      ),
      home: const SimulatorScreen(),
    );
  }
}
