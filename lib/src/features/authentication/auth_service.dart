import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend_service.dart';
import 'user_model.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static bool _userStatsTableAvailable = true;
  static bool _userBadgesTableAvailable = true;

  /// Sign up a new user
  Future<UserProfile?> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'name': name},
      );

      if (response.user != null) {
        return UserProfile(
          id: response.user!.id,
          email: response.user!.email!,
          name: name,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Sign up error: $e');
      rethrow;
    }
  }

  /// Sign in an existing user
  Future<UserProfile?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null) {
        return _buildUserProfile(response.user!);
      }
      return null;
    } catch (e) {
      debugPrint('Sign in error: $e');
      rethrow;
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Sign out error: $e');
      rethrow;
    }
  }

  /// Get the current authenticated user
  Future<UserProfile?> getCurrentUser() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        return _buildUserProfile(user);
      }
      return null;
    } catch (e) {
      debugPrint('Get current user error: $e');
      return null;
    }
  }

  Future<UserProfile> _buildUserProfile(User user) async {
    final userData = user.userMetadata ?? {};
    var isVerified = user.phoneConfirmedAt != null;
    String? phoneNumber = _cleanPhoneNumber(user.phone);
    var points = 0;
    var streak = 0;
    var badges = <String>[];

    try {
      final profileResponse =
          await _supabase
              .from('profiles')
              .select('preferences')
              .eq('id', user.id)
              .maybeSingle();

      if (profileResponse != null) {
        final prefs = profileResponse['preferences'];
        if (prefs is Map) {
          isVerified = isVerified || prefs['is_phone_verified'] == true;
          final rawPhone = prefs['phone_number'];
          if (rawPhone is String && rawPhone.trim().isNotEmpty) {
            phoneNumber = rawPhone.trim();
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile data: $e');
    }

    if (_userStatsTableAvailable) {
      try {
        final statsResponse =
            await _supabase
                .from('user_stats')
                .select('total_points, current_streak')
                .eq('user_id', user.id)
                .maybeSingle();

        if (statsResponse != null) {
          points = statsResponse['total_points'] ?? 0;
          streak = statsResponse['current_streak'] ?? 0;
        }
      } catch (e) {
        _userStatsTableAvailable = !_isMissingTableError(e);
        debugPrint('Error fetching user stats: $e');
      }
    }

    if (_userBadgesTableAvailable) {
      try {
        final badgesResponse = await _supabase
            .from('user_badges')
            .select('badge_id')
            .eq('user_id', user.id);

        badges =
            (badgesResponse as List)
                .map((e) => e['badge_id'] as String)
                .toList();
      } catch (e) {
        _userBadgesTableAvailable = !_isMissingTableError(e);
        debugPrint('Error fetching user badges: $e');
      }
    }

    return UserProfile(
      id: user.id,
      email: user.email!,
      name: userData['name'] ?? '',
      profileImageUrl: userData['profile_image_url'],
      phoneNumber: phoneNumber,
      isPhoneVerified: isVerified,
      points: points,
      streak: streak,
      badges: badges,
    );
  }

  bool _isMissingTableError(Object error) {
    final message = error.toString();
    return message.contains('PGRST205') ||
        message.contains("Could not find the table 'public.");
  }

  /// Get the current session access token
  String? getAuthToken() {
    return _supabase.auth.currentSession?.accessToken;
  }

  /// Check if user is authenticated
  bool isAuthenticated() {
    return _supabase.auth.currentUser != null;
  }

  /// Listen to auth state changes
  Stream<AuthState> get authStateChanges {
    return _supabase.auth.onAuthStateChange;
  }

  /// Get current user ID
  String? get currentUserId {
    return _supabase.auth.currentUser?.id;
  }

  /// Update user profile (name, email)
  Future<UserProfile?> updateProfile({String? name, String? email}) async {
    try {
      final response = await _supabase.auth.updateUser(
        UserAttributes(
          email: email,
          data: name != null ? {'name': name} : null,
        ),
      );

      if (response.user != null) {
        final userData = response.user!.userMetadata ?? {};
        return UserProfile(
          id: response.user!.id,
          email: response.user!.email!,
          name: userData['name'] ?? '',
          profileImageUrl: userData['profile_image_url'],
          phoneNumber: _cleanPhoneNumber(response.user!.phone),
          isPhoneVerified: response.user!.phoneConfirmedAt != null,
        );
      }
      return null;
    } catch (e) {
      debugPrint('Update profile error: $e');
      rethrow;
    }
  }

  /// Change password
  Future<void> changePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      debugPrint('Change password error: $e');
      rethrow;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      debugPrint('Password reset error: $e');
      rethrow;
    }
  }

  /// Delete user account
  Future<void> deleteAccount() async {
    try {
      final accessToken = _supabase.auth.currentSession?.accessToken;
      if (accessToken == null) {
        throw Exception('You must be signed in to delete your account.');
      }

      await BackendService.delete(
        '/api/users/me',
        headers: {'Authorization': 'Bearer $accessToken'},
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
      await _supabase.auth.updateUser(UserAttributes(phone: normalizedPhone));
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
      await _supabase.auth.verifyOTP(
        phone: normalizedPhone,
        token: otp.trim(),
        type: OtpType.phoneChange,
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
