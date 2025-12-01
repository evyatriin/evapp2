import 'package:supabase_flutter/supabase_flutter.dart';
import 'user_model.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

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
      print('Sign up error: $e');
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
        final userData = response.user!.userMetadata ?? {};
        return UserProfile(
          id: response.user!.id,
          email: response.user!.email!,
          name: userData['name'] ?? '',
          profileImageUrl: userData['profile_image_url'],
        );
      }
      return null;
    } catch (e) {
      print('Sign in error: $e');
      rethrow;
    }
  }

  /// Sign out the current user
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      print('Sign out error: $e');
      rethrow;
    }
  }

  /// Get the current authenticated user
  Future<UserProfile?> getCurrentUser() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final userData = user.userMetadata ?? {};
        return UserProfile(
          id: user.id,
          email: user.email!,
          name: userData['name'] ?? '',
          profileImageUrl: userData['profile_image_url'],
        );
      }
      return null;
    } catch (e) {
      print('Get current user error: $e');
      return null;
    }
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
  Future<UserProfile?> updateProfile({
    String? name,
    String? email,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) {
        updates['data'] = {'name': name};
      }
      if (email != null) {
        updates['email'] = email;
      }

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
        );
      }
      return null;
    } catch (e) {
      print('Update profile error: $e');
      rethrow;
    }
  }

  /// Change password
  Future<void> changePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
    } catch (e) {
      print('Change password error: $e');
      rethrow;
    }
  }

  /// Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      print('Password reset error: $e');
      rethrow;
    }
  }

  /// Delete user account
  Future<void> deleteAccount() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        // Note: Supabase doesn't have a direct delete user method from client
        // This would typically be done via an admin API or Edge Function
        // For now, we'll just sign out
        await signOut();
      }
    } catch (e) {
      print('Delete account error: $e');
      rethrow;
    }
  }
}
