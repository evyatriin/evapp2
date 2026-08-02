import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend_service.dart';
import 'user_model.dart';

/// Deep link Supabase redirects back to after an OAuth (Google/Apple) sign-in.
/// Must be registered in the Android manifest, the iOS Info.plist, AND added to
/// the Supabase dashboard's "Redirect URLs" allow-list. See OAUTH_SETUP.md.
const String kOAuthRedirectUri = 'io.supabase.evraahein://login-callback/';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Kept only as an in-memory fallback for the current run. The source of
  // truth is the persisted Supabase session (survives restarts + auto-refreshes).
  static String? _currentAuthToken;
  static String? _currentUserId;

  /// Current access token — read from the persisted Supabase session first so
  /// it stays valid across app restarts and after silent token refreshes.
  String? getAuthToken() =>
      _supabase.auth.currentSession?.accessToken ?? _currentAuthToken;

  /// Persist the tokens returned by the backend into the Supabase client so the
  /// session is saved to disk and auto-refreshed. Without this the user was
  /// silently logged out on every relaunch.
  Future<void> _persistSession({
    required String? accessToken,
    required String? refreshToken,
    String? userId,
  }) async {
    _currentAuthToken = accessToken;
    _currentUserId = userId;

    if (accessToken == null || refreshToken == null) return;
    try {
      await _supabase.auth.setSession(refreshToken, accessToken: accessToken);
    } catch (e) {
      debugPrint('Supabase session persistence warning: $e');
    }
  }

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
          await _persistSession(
            accessToken: sessionData['access_token'] as String?,
            refreshToken: sessionData['refresh_token'] as String?,
            userId: userData['id'] as String?,
          );

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
          await _persistSession(
            accessToken: sessionData['access_token'] as String?,
            refreshToken: sessionData['refresh_token'] as String?,
            userId: userData['id'] as String?,
          );

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

  /// Start an OAuth sign-in (Google / Apple) via Supabase.
  ///
  /// This launches the provider's sign-in page; the session is delivered back
  /// asynchronously through the [kOAuthRedirectUri] deep link and surfaces via
  /// `supabase.auth.onAuthStateChange` (listened to in the User provider).
  /// Returns whether the auth flow was successfully launched.
  Future<bool> signInWithOAuth(OAuthProvider provider) async {
    return _supabase.auth.signInWithOAuth(
      provider,
      redirectTo: kIsWeb ? null : kOAuthRedirectUri,
    );
  }

  /// Sign out the current user
  Future<void> signOut() async {
    final token = getAuthToken();
    try {
      debugPrint('Signing out user');
      if (token != null) {
        await BackendService.post(
          '/api/auth/logout',
          body: {},
          headers: {
            'Authorization': 'Bearer $token',
          },
        );
      }
    } catch (e) {
      debugPrint('Sign out backend warning: $e');
    } finally {
      _currentAuthToken = null;
      _currentUserId = null;
      try {
        await _supabase.auth.signOut();
      } catch (_) {}
    }
  }

  /// Get the current authenticated user
  Future<UserProfile?> getCurrentUser() async {
    final token = getAuthToken();
    try {
      if (token == null) {
        return null;
      }

      debugPrint('Fetching current user from backend');

      final response = await BackendService.get(
        '/api/auth/user',
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response is Map<String, dynamic>) {
        debugPrint('Current user fetched: ${response['email']}');
        _currentUserId = response['id'] as String?;
        // Email is verified if the backend says so, or the persisted Supabase
        // session shows a confirmed email (covers OAuth users too).
        final emailVerified = (response['email_verified'] as bool? ?? false) ||
            _supabase.auth.currentUser?.emailConfirmedAt != null;
        return UserProfile(
          id: response['id'] as String,
          email: response['email'] as String,
          name: response['name'] as String? ?? '',
          profileImageUrl: response['profile_image_url'] as String?,
          phoneNumber: response['phone_number'] as String?,
          isPhoneVerified: response['is_phone_verified'] as bool? ?? false,
          isEmailVerified: emailVerified,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Get current user error: $e');
      return null;
    }
  }

  /// Check if user is authenticated
  bool isAuthenticated() {
    return _supabase.auth.currentSession != null || _currentAuthToken != null;
  }

  /// Get current user ID (from the persisted session, falling back to memory)
  String? get currentUserId =>
      _supabase.auth.currentUser?.id ?? _currentUserId;

  /// Update user profile (name) via backend API.
  Future<UserProfile?> updateProfile({String? name, String? email}) async {
    final token = getAuthToken();
    final uid = currentUserId;
    if (token == null || uid == null) {
      throw Exception('You must be signed in to update your profile.');
    }
    await BackendService.put(
      '/api/users/profile',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'user_id': uid,
        if (name != null) 'name': name,
      },
    );
    return getCurrentUser();
  }

  /// Change password via backend API (requires service role on backend).
  Future<void> changePassword(String newPassword) async {
    final token = getAuthToken();
    if (token == null) {
      throw Exception('You must be signed in to change your password.');
    }
    await BackendService.post(
      '/api/auth/change-password',
      headers: {'Authorization': 'Bearer $token'},
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
    final token = getAuthToken();
    try {
      if (token == null) {
        throw Exception('You must be signed in to delete your account.');
      }

      await BackendService.delete(
        '/api/users/me',
        headers: {'Authorization': 'Bearer $token'},
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
      final token = getAuthToken();
      if (token == null) {
        throw Exception('You must be signed in to request phone verification.');
      }

      await BackendService.post(
        '/api/auth/request-phone-verification',
        body: {'phone_number': normalizedPhone},
        headers: {'Authorization': 'Bearer $token'},
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
      final token = getAuthToken();
      if (token == null) {
        throw Exception('You must be signed in to verify phone OTP.');
      }

      await BackendService.post(
        '/api/auth/verify-phone-otp',
        body: {
          'phone_number': normalizedPhone,
          'otp': otp.trim(),
        },
        headers: {'Authorization': 'Bearer $token'},
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
}
