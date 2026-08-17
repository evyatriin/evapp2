import 'dart:async';

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
  StreamSubscription<AuthState>? _authSubscription;

  @override
  UserProfile? build() {
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      event,
    ) {
      switch (event.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.tokenRefreshed:
          unawaited(_loadCurrentUser());
          break;
        case AuthChangeEvent.signedOut:
          state = null;
          break;
        default:
          if (event.session == null) {
            state = null;
          }
      }
    });
    ref.onDispose(() => _authSubscription?.cancel());
    _loadCurrentUser();
    return null;
  }

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
    required bool termsAccepted,
  }) async {
    try {
      final user = await _authService.signUp(
        email: email,
        password: password,
        name: name,
        termsAccepted: termsAccepted,
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
    String? name,
    String phoneNumber = '',
    bool isPhoneVerified = false,
    Map<String, dynamic> vehicleDetails = const {},
  }) async {
    try {
      if (state == null) throw Exception('User not logged in');

      if (name != null && name.trim().isNotEmpty) {
        await BackendService.put('/api/users/me', body: {'name': name.trim()});

        if (state != null) {
          state = state!.copyWith(name: name.trim());
        }
        return;
      }

      await BackendService.put(
        '/api/users/profile',
        body: {
          'user_id': state!.id,
          'phone_number': phoneNumber,
          'is_phone_verified': isPhoneVerified,
          'vehicle_details': vehicleDetails,
        },
      );

      if (state != null) {
        state = state!.copyWith(
          phoneNumber: phoneNumber.isEmpty ? state!.phoneNumber : phoneNumber,
          isPhoneVerified: isPhoneVerified,
        );
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
