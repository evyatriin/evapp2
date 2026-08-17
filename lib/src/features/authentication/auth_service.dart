import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend_service.dart';
import 'user_model.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? getAuthToken() => currentToken;

  static String? get currentToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  bool isAuthenticated() => _supabase.auth.currentSession != null;

  Future<void> restoreSession() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return;

    if (session.isExpired) {
      try {
        await _supabase.auth.refreshSession();
      } on AuthException {
        await _supabase.auth.signOut(scope: SignOutScope.local);
      }
    }
  }

  Future<UserProfile?> signUp({
    required String email,
    required String password,
    required String name,
    required bool termsAccepted,
  }) async {
    final response = await BackendService.post(
      '/api/auth/signup',
      body: {
        'email': email,
        'password': password,
        'name': name,
        'terms_accepted': termsAccepted,
      },
      authenticated: false,
    );

    if (response is! Map<String, dynamic>) {
      throw const BackendException(
        statusCode: 502,
        message: 'The signup service returned an invalid response.',
      );
    }

    final userData = response['user'] as Map<String, dynamic>?;
    final sessionData = response['session'] as Map<String, dynamic>?;
    if (userData == null) {
      throw const BackendException(
        statusCode: 502,
        message: 'The signup service returned an invalid user.',
      );
    }

    final refreshToken = sessionData?['refresh_token'] as String?;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _supabase.auth.setSession(refreshToken);
    }

    return UserProfile(
      id: userData['id'] as String,
      email: userData['email'] as String? ?? email,
      name: userData['name'] as String? ?? name,
    );
  }

  Future<UserProfile?> signIn({
    required String email,
    required String password,
  }) async {
    final response = await BackendService.post(
      '/api/auth/login',
      body: {'email': email, 'password': password},
      authenticated: false,
    );

    if (response is! Map<String, dynamic>) {
      throw const BackendException(
        statusCode: 502,
        message: 'The login service returned an invalid response.',
      );
    }

    final userData = response['user'] as Map<String, dynamic>?;
    final sessionData = response['session'] as Map<String, dynamic>?;
    final refreshToken = sessionData?['refresh_token'] as String?;
    if (userData == null || refreshToken == null || refreshToken.isEmpty) {
      throw const BackendException(
        statusCode: 401,
        message: 'Unable to start a secure login session.',
      );
    }

    await _supabase.auth.setSession(refreshToken);
    return UserProfile(
      id: userData['id'] as String,
      email: userData['email'] as String? ?? email,
      name: userData['name'] as String? ?? '',
    );
  }

  Future<void> signOut() async {
    try {
      if (currentToken != null) {
        await BackendService.post('/api/auth/logout', body: {});
      }
    } catch (error) {
      debugPrint('Remote sign-out warning: $error');
    } finally {
      await _supabase.auth.signOut(scope: SignOutScope.local);
    }
  }

  Future<UserProfile?> getCurrentUser() async {
    await restoreSession();
    if (_supabase.auth.currentSession == null) return null;

    try {
      final response = await BackendService.get('/api/auth/user');
      if (response is! Map<String, dynamic>) return null;
      return UserProfile(
        id: response['id'] as String,
        email: response['email'] as String? ?? '',
        name: response['name'] as String? ?? '',
        profileImageUrl: response['profile_image_url'] as String?,
        phoneNumber: response['phone_number'] as String?,
        isPhoneVerified: response['is_phone_verified'] as bool? ?? false,
        points: response['points'] as int? ?? 0,
        streak: response['streak'] as int? ?? 0,
        badges:
            (response['badges'] as List<dynamic>?)
                ?.map((item) => item.toString())
                .toList() ??
            const [],
      );
    } on BackendException catch (error) {
      if (error.statusCode == 401) {
        await _supabase.auth.signOut(scope: SignOutScope.local);
        return null;
      }
      rethrow;
    }
  }

  Future<UserProfile?> updateProfile({String? name, String? email}) async {
    if (!isAuthenticated()) {
      throw const BackendException(
        statusCode: 401,
        message: 'You must be signed in to update your profile.',
      );
    }
    await BackendService.put(
      '/api/users/me',
      body: {if (name != null) 'name': name},
    );
    return getCurrentUser();
  }

  Future<void> changePassword(String newPassword) async {
    await BackendService.post(
      '/api/auth/change-password',
      body: {'new_password': newPassword},
    );
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await BackendService.post(
      '/api/auth/reset-password',
      body: {'email': email},
      authenticated: false,
    );
  }

  Future<void> deleteAccount() async {
    await BackendService.delete('/api/users/me');
    await _supabase.auth.signOut(scope: SignOutScope.local);
  }

  Future<String> requestPhoneVerification(String phoneNumber) {
    throw const BackendException(
      statusCode: 503,
      message: 'Phone verification is not available in this release.',
    );
  }

  Future<void> verifyPhoneOtp({
    required String phoneNumber,
    required String otp,
  }) {
    throw const BackendException(
      statusCode: 503,
      message: 'Phone verification is not available in this release.',
    );
  }

  String? normalizePhoneNumber(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('+')) {
      return digits.length >= 8 ? digits : null;
    }

    final numericOnly = digits.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericOnly.length == 10) return '+91$numericOnly';
    if (numericOnly.length >= 8) return '+$numericOnly';
    return null;
  }
}
