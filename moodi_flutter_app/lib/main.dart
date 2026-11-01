import 'package:flutter/material.dart';

import 'screens/moodi_home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MoodiApp());
}

class MoodiApp extends StatelessWidget {
  const MoodiApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF0B0E14);
    const accent = Color(0xFF79E5D2);

    return MaterialApp(
      title: 'MOODI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.dark,
          surface: const Color(0xFF151B24),
        ),
        fontFamily: 'Roboto',
      ),
      home: const MoodiHomePage(),
    );
  }
}
