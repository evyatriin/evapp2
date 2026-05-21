import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend_service.dart';
import '../../core/app_config.dart';
import 'user_model.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static bool _userStatsTableAvailable = true;
  static bool _userBadgesTableAvailable = true;
  static String? _currentAuthToken;
  static String? _currentRefreshToken;
  static String? _currentUserId;

  /// Get the current auth token
  String? getAuthToken() => _currentAuthToken;

  /// Sign up a new user via backend API
  Future<UserProfile?> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      debugPrint('Attempting signup for email: $email via backend API');

      final response = await BackendService.post(
        '/api/auth/signup',
        body: {
          'email': email,
          'password': password,
          'name': name,
        },
      );

      debugPrint('Signup response: $response');

      if (response is Map<String, dynamic>) {
        final userData = response['user'] as Map<String, dynamic>?;
        final sessionData = response['session'] as Map<String, dynamic>?;

        if (userData != null && sessionData != null) {
          _currentAuthToken = sessionData['access_token'] as String?;
          _currentRefreshToken = sessionData['refresh_token'] as String?;
          _currentUserId = userData['id'] as String?;

          // Sync Supabase Flutter client so currentSession is available
          // to services (e.g. RemoteChargerService) that read it directly.
          if (_currentAuthToken != null && _currentRefreshToken != null) {
            try {
              await _supabase.auth.setSession(_currentAuthToken!);
            } catch (e) {
              debugPrint('Supabase session sync warning (signup): $e');
            }
          }

          debugPrint('Signup successful for user: ${userData['email']}');
          return UserProfile(
            id: userData['id'] as String,
            email: userData['email'] as String,
            name: userData['name'] as String? ?? name,
          );
        }
      }
      throw Exception('Signup failed: Invalid response from server');
    } catch (e) {
      debugPrint('Sign up error: $e');
      rethrow;
    }
  }

  /// Sign in an existing user via backend API
  Future<UserProfile?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('Attempting signin for email: $email via backend API');

      final response = await BackendService.post(
        '/api/auth/login',
        body: {
          'email': email,
          'password': password,
        },
      );

      debugPrint('Login response: $response');

      if (response is Map<String, dynamic>) {
        final userData = response['user'] as Map<String, dynamic>?;
        final sessionData = response['session'] as Map<String, dynamic>?;

        if (userData != null && sessionData != null) {
          _currentAuthToken = sessionData['access_token'] as String?;
          _currentRefreshToken = sessionData['refresh_token'] as String?;
          _currentUserId = userData['id'] as String?;

          // Sync Supabase Flutter client so currentSession is available
          // to services (e.g. RemoteChargerService) that read it directly.
          if (_currentAuthToken != null) {
            try {
              await _supabase.auth.setSession(_currentAuthToken!);
            } catch (e) {
              debugPrint('Supabase session sync warning (login): $e');
            }
          }

          debugPrint('Login successful for user: ${userData['email']}');
          return UserProfile(
            id: userData['id'] as String,
            email: userData['email'] as String,
            name: userData['name'] as String? ?? '',
          );
        }
      }
      throw Exception('Login failed: Invalid credentials or server error');
    } catch (e) {
      debugPrint('Sign in error: $e');
      rethrow;
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      debugPrint('Signing out user');
      if (_currentAuthToken != null) {
        await BackendService.post(
          '/api/auth/logout',
          body: {},
          headers: {
            'Authorization': 'Bearer $_currentAuthToken',
          },
        );
      }
      _currentAuthToken = null;
      _currentRefreshToken = null;
      _currentUserId = null;
      try { await _supabase.auth.signOut(); } catch (_) {}
    } catch (e) {
      debugPrint('Sign out error: $e');
      _currentAuthToken = null;
      _currentRefreshToken = null;
      _currentUserId = null;
      try { await _supabase.auth.signOut(); } catch (_) {}
      rethrow;
    }
  }

  /// Get the current authenticated user
  Future<UserProfile?> getCurrentUser() async {
    try {
      if (_currentAuthToken == null) {
        return null;
      }

      debugPrint('Fetching current user from backend');

      final response = await BackendService.get(
        '/api/auth/user',
        headers: {
          'Authorization': 'Bearer $_currentAuthToken',
        },
      );

      if (response is Map<String, dynamic>) {
        debugPrint('Current user fetched: ${response['email']}');
        _currentUserId = response['id'] as String?;
        return UserProfile(
          id: response['id'] as String,
          email: response['email'] as String,
          name: response['name'] as String? ?? '',
        );
      }
      return null;
    } catch (e) {
      debugPrint('Get current user error: $e');
      _currentAuthToken = null;
      _currentUserId = null;
      return null;
    }
  }

  /// Check if user is authenticated
  bool isAuthenticated() {
    return _currentAuthToken != null;
  }

  /// Get current user ID (stored locally after login)
  String? get currentUserId => _currentUserId;

  /// Update user profile (name) via backend API.
  Future<UserProfile?> updateProfile({String? name, String? email}) async {
    if (_currentAuthToken == null || _currentUserId == null) {
      throw Exception('You must be signed in to update your profile.');
    }
    await BackendService.put(
      '/api/users/profile',
      headers: {'Authorization': 'Bearer $_currentAuthToken'},
      body: {
        'user_id': _currentUserId,
        if (name != null) 'name': name,
      },
    );
    return getCurrentUser();
  }

  /// Change password via backend API (requires service role on backend).
  Future<void> changePassword(String newPassword) async {
    if (_currentAuthToken == null) {
      throw Exception('You must be signed in to change your password.');
    }
    await BackendService.post(
      '/api/auth/change-password',
      headers: {'Authorization': 'Bearer $_currentAuthToken'},
      body: {'new_password': newPassword},
    );
  }

  /// Send password reset email. Always succeeds (backend hides enumeration).
  Future<void> sendPasswordResetEmail(String email) async {
    await BackendService.post(
      '/api/auth/reset-password',
      body: {'email': email},
    );
  }

  /// Delete user account
  Future<void> deleteAccount() async {
    try {
      if (_currentAuthToken == null) {
        throw Exception('You must be signed in to delete your account.');
      }

      await BackendService.delete(
        '/api/users/me',
        headers: {'Authorization': 'Bearer $_currentAuthToken'},
      );
      await signOut();
    } catch (e) {
      debugPrint('Delete account error: $e');
      rethrow;
    }
  }

  Future<String> requestPhoneVerification(String phoneNumber) async {
    final normalizedPhone = normalizePhoneNumber(phoneNumber);
    if (normalizedPhone == null) {
      throw Exception(
        'Enter a valid phone number with country code. Indian 10-digit numbers are supported automatically.',
      );
    }

    try {
      if (_currentAuthToken == null) {
        throw Exception('You must be signed in to request phone verification.');
      }

      await BackendService.post(
        '/api/auth/request-phone-verification',
        body: {'phone_number': normalizedPhone},
        headers: {'Authorization': 'Bearer $_currentAuthToken'},
      );
      return normalizedPhone;
    } catch (e) {
      debugPrint('Request phone verification error: $e');
      rethrow;
    }
  }

  Future<void> verifyPhoneOtp({
    required String phoneNumber,
    required String otp,
  }) async {
    final normalizedPhone = normalizePhoneNumber(phoneNumber);
    if (normalizedPhone == null) {
      throw Exception('Enter a valid phone number before verifying.');
    }
    if (otp.trim().isEmpty) {
      throw Exception('Enter the OTP sent to your phone.');
    }

    try {
      if (_currentAuthToken == null) {
        throw Exception('You must be signed in to verify phone OTP.');
      }

      await BackendService.post(
        '/api/auth/verify-phone-otp',
        body: {
          'phone_number': normalizedPhone,
          'otp': otp.trim(),
        },
        headers: {'Authorization': 'Bearer $_currentAuthToken'},
      );
    } catch (e) {
      debugPrint('Verify phone OTP error: $e');
      rethrow;
    }
  }

  String? normalizePhoneNumber(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) {
      return null;
    }
    if (digits.startsWith('+')) {
      return digits.length >= 8 ? digits : null;
    }

    final numericOnly = digits.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericOnly.length == 10) {
      return '+91$numericOnly';
    }
    if (numericOnly.length >= 8) {
      return '+$numericOnly';
    }
    return null;
  }

  String? _cleanPhoneNumber(String? phoneNumber) {
    final trimmed = phoneNumber?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
