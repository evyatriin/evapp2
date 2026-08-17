// Standalone preview harness for the Beckn/UEI "Discover & Charge" screen.
//
// Run with:
//   flutter run -t lib/preview_beckn.dart
//
// This renders BecknNetworkScreen with the real app theme but WITHOUT booting
// Supabase, auth, ads, or maps — so it works with no API keys or backend.
// It exists only for design review / pitch screenshots and is not shipped.
import 'package:flutter/material.dart';
import 'src/core/theme.dart';
import 'src/features/beckn/beckn_network_screen.dart';

void main() {
  runApp(const _PreviewApp());
}

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EVraahein — Open Network preview',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light,
      debugShowCheckedModeBanner: false,
      home: const BecknNetworkScreen(),
    );
  }
}
