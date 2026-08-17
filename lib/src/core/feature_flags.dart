import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_config.dart';

/// Remote feature flags fetched from backend.
/// All Beckn features are disabled by default until flag is fetched.
class FeatureFlags {
  static bool _becknChargingEnabled = false;
  static bool _loaded = false;

  static bool get becknChargingEnabled => _becknChargingEnabled;
  static bool get qrScannerEnabled => _becknChargingEnabled;
  static bool get loaded => _loaded;

  /// Call this once at app startup (in main.dart or app initialisation).
  static Future<void> load() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.backendBaseUrl}/api/chargers/feature-flags',
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _becknChargingEnabled = data['beckn_charging'] == true;
      }
    } catch (e) {
      // Silently fail — flags stay false
      if (kDebugMode) print('FeatureFlags.load failed: $e');
    } finally {
      _loaded = true;
    }
  }

  /// For development/testing override.
  static void setForTesting({bool becknCharging = false}) {
    _becknChargingEnabled = becknCharging;
    _loaded = true;
  }
}
