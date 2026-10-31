import 'package:flutter/material.dart';
import 'suite_switch_demo_view.dart';

void main() {
  runApp(const DZeroBenchmarkApp());
}

class DZeroBenchmarkApp extends StatelessWidget {
  const DZeroBenchmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D-Zero Benchmark Suite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF090A0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF88),
          secondary: Color(0xFF00E5FF),
          surface: Color(0xFF121420),
        ),
      ),
      home: const BenchmarkHomeScreen(),
    );
  }
}

class BenchmarkHomeScreen extends StatelessWidget {
  const BenchmarkHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF121420),
        title: const Text(
          '⚡️ D-Zero',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: const SuiteSwitchDemoView(),
    );
  }
}
