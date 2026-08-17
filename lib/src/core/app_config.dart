import 'dart:io';

import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  static const String _backendUrl = String.fromEnvironment('BACKEND_URL');
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const bool sosEnabled = bool.fromEnvironment(
    'SOS_ENABLED',
    defaultValue: false,
  );
  static const bool releaseAdsEnabled = bool.fromEnvironment(
    'ADS_ENABLED',
    defaultValue: false,
  );

  static const String _androidReleaseBannerAdUnitId = String.fromEnvironment(
    'ADMOB_BANNER_ANDROID',
  );
  static const String _iosReleaseBannerAdUnitId = String.fromEnvironment(
    'ADMOB_BANNER_IOS',
  );

  static const String _androidTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _iosTestBannerAdUnitId =
      'ca-app-pub-3940256099942544/2934735716';

  static String get backendBaseUrl {
    final resolved = _backendUrl;
    return resolved.endsWith('/')
        ? resolved.substring(0, resolved.length - 1)
        : resolved;
  }

  static bool get hasBackendConfig => _backendUrl.isNotEmpty;

  static String? get backendConfigError {
    if (_backendUrl.isEmpty) {
      return 'Missing BACKEND_URL. Rebuild the app with your Cloud Run backend URL.';
    }

    final uri = Uri.tryParse(_backendUrl);
    if (uri == null || !uri.isAbsolute || !_backendUrl.startsWith('https://')) {
      return 'BACKEND_URL is invalid. Rebuild the app with a valid https:// Cloud Run URL.';
    }

    return null;
  }

  static bool get hasSupabaseConfig =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  static String get supabaseUrl => _supabaseUrl;

  static String get supabaseAnonKey => _supabaseAnonKey;

  static String? get supabaseConfigError {
    if (_supabaseUrl.isEmpty && _supabaseAnonKey.isEmpty) {
      return 'Missing Supabase configuration. Rebuild the app with SUPABASE_URL and SUPABASE_ANON_KEY.';
    }
    if (_supabaseUrl.isEmpty) {
      return 'Missing SUPABASE_URL. Rebuild the app with a valid Supabase project URL.';
    }
    if (_supabaseAnonKey.isEmpty) {
      return 'Missing SUPABASE_ANON_KEY. Rebuild the app with a valid Supabase anon key.';
    }
    final uri = Uri.tryParse(_supabaseUrl);
    if (uri == null ||
        !uri.isAbsolute ||
        !_supabaseUrl.startsWith('https://')) {
      return 'SUPABASE_URL is invalid. Rebuild the app with a valid https://<project>.supabase.co URL.';
    }
    return null;
  }

  static bool get adsEnabled {
    if (kDebugMode) return true;
    if (!releaseAdsEnabled) return false;

    return Platform.isAndroid
        ? _androidReleaseBannerAdUnitId.isNotEmpty
        : _iosReleaseBannerAdUnitId.isNotEmpty;
  }

  static String? get bannerAdUnitId {
    if (Platform.isAndroid) {
      if (kDebugMode) return _androidTestBannerAdUnitId;
      return _androidReleaseBannerAdUnitId.isEmpty
          ? null
          : _androidReleaseBannerAdUnitId;
    }

    if (kDebugMode) return _iosTestBannerAdUnitId;
    return _iosReleaseBannerAdUnitId.isEmpty ? null : _iosReleaseBannerAdUnitId;
  }
}
