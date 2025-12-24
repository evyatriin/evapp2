import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'src/core/router.dart';
import 'src/core/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize AdMob
  await MobileAds.instance.initialize();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://mzxwbfpxmyjmbfhosgkk.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im16eHdiZnB4bXlqbWJmaG9zZ2trIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ1NTY0NjIsImV4cCI6MjA4MDEzMjQ2Mn0.dX-ZkKDOgXfOeyYrkyA77NLZmM-sWyf2zjXfVp7zFWg',
  );
  
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'EV-Ranger',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
