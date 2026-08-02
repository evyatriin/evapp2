import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/backend_service.dart';
import 'auth_service.dart';
import 'user_model.dart';

part 'user_provider.g.dart';

@riverpod
class User extends _$User {
  final _authService = AuthService();

  @override
  UserProfile? build() {
    // React to Supabase auth changes: session restored on launch, OAuth
    // (Google/Apple) sign-in arriving via deep link, silent token refresh, and
    // sign-out. This is what keeps the user logged in across app restarts.
    final sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.tokenRefreshed:
          _loadCurrentUser();
          break;
        case AuthChangeEvent.signedOut:
          if (ref.mounted) state = null;
          break;
        default:
          break;
      }
    });
    ref.onDispose(sub.cancel);

    // Also kick off an immediate load for the current run.
    _loadCurrentUser();
    return null; // Will be populated by _loadCurrentUser
  }

  /// Start a Google/Apple OAuth sign-in. The resulting session arrives via the
  /// deep-link callback and is picked up by the auth-state listener above.
  Future<bool> signInWithOAuth(OAuthProvider provider) {
    return _authService.signInWithOAuth(provider);
  }

  Future<void> _loadCurrentUser() async {
    final user = await _authService.getCurrentUser();
    // Check if provider is still mounted before updating state
    if (ref.mounted) {
      state = user;
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    try {
      final user = await _authService.signUp(
        email: email,
        password: password,
        name: name,
      );
      state = user;
    } catch (e) {
      debugPrint('Sign up error in provider: $e');
      rethrow;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      final user = await _authService.signIn(email: email, password: password);
      state = user;
    } catch (e) {
      debugPrint('Sign in error in provider: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _authService.signOut();
      state = null;
    } catch (e) {
      debugPrint('Sign out error in provider: $e');
      rethrow;
    }
  }

  Future<void> completeOnboarding({
    required String phoneNumber,
    required bool isPhoneVerified,
    required Map<String, dynamic> vehicleDetails,
  }) async {
    try {
      if (state == null) throw Exception('User not logged in');

      await BackendService.put(
        '/api/users/profile',
        body: {
          'user_id': state!.id,
          'phone_number': phoneNumber,
          'is_phone_verified': isPhoneVerified,
          'vehicle_details': vehicleDetails,
        },
        headers: {
          if (_authService.getAuthToken() case final token?) 'Authorization': 'Bearer $token',
        },
      );

      // Update local state
      if (state != null) {
        state = state!.copyWith(isPhoneVerified: isPhoneVerified);
      }
    } catch (e) {
      debugPrint('Onboarding error: $e');
      rethrow;
    }
  }

  Future<void> refresh() async {
    await _loadCurrentUser();
  }

  Future<void> deleteAccount() async {
    try {
      await _authService.deleteAccount();
      state = null;
    } catch (e) {
      debugPrint('Delete account error in provider: $e');
      rethrow;
    }
  }

  void updateName(String name) {
    if (state != null) {
      state = state!.copyWith(name: name);
    }
  }

  String? get userId => state?.id;

  bool get isAuthenticated => state != null;
}
