import 'package:flutter/material.dart';

import 'presentation/home.dart';

void main() => runApp(const ClearSafeApp());

class ClearSafeApp extends StatelessWidget {
  const ClearSafeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'ClearSafe',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff167568)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff4f7f6),
    ),
    home: const Home(),
  );
}
