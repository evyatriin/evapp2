import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'user_model.dart';
import 'auth_service.dart';

part 'user_provider.g.dart';

@riverpod
class User extends _$User {
  final _authService = AuthService();

  @override
  UserProfile? build() {
    // Load current user from Supabase Auth
    _loadCurrentUser();
    return null; // Will be populated by _loadCurrentUser
  }

  Future<void> _loadCurrentUser() async {
    final user = await _authService.getCurrentUser();
    state = user;
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
      print('Sign up error in provider: $e');
      rethrow;
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final user = await _authService.signIn(
        email: email,
        password: password,
      );
      state = user;
    } catch (e) {
      print('Sign in error in provider: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _authService.signOut();
      state = null;
    } catch (e) {
      print('Sign out error in provider: $e');
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
