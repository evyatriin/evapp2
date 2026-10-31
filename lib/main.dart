import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'src/core/app_config.dart';
import 'src/core/router.dart';
import 'src/core/theme.dart';

Future<void> main() async {
  await SentryFlutter.init((options) {
    options.dsn = const String.fromEnvironment('SENTRY_DSN', defaultValue: '');
    options.environment = kReleaseMode ? 'production' : 'debug';
    options.tracesSampleRate = kReleaseMode ? 0.2 : 0.0;
    options.attachScreenshot = true;
  }, appRunner: () => _boot());
}

Future<void> _boot() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.adsEnabled) {
    await MobileAds.instance.initialize();
  }

  final configError =
      AppConfig.backendConfigError ?? AppConfig.supabaseConfigError;
  if (configError != null) {
    runApp(_ConfigurationErrorApp(message: configError));
    return;
  }

  // Warm the Cloud Run backend (defeats cold start) while the user reads the
  // login screen. Fire-and-forget — failures are harmless.
  unawaited(_warmBackend());

  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
    );
    runApp(const ProviderScope(child: MyApp()));
  } catch (error, stack) {
    await Sentry.captureException(error, stackTrace: stack);
    runApp(
      _ConfigurationErrorApp(
        message:
            'App services could not be reached. Check BACKEND_URL, SUPABASE_URL, and your network connection, then rebuild the app.',
        details: kDebugMode ? error.toString() : null,
      ),
    );
  }
}

Future<void> _warmBackend() async {
  try {
    await http
        .get(Uri.parse('${AppConfig.backendBaseUrl}/health'))
        .timeout(const Duration(seconds: 6));
  } catch (_) {
    // Best-effort warm-up only.
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'EVraahein',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class _ConfigurationErrorApp extends StatelessWidget {
  const _ConfigurationErrorApp({required this.message, this.details});

  final String message;
  final String? details;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_outlined,
                    size: 72,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Configuration Needed',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (details != null && details!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      details!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
