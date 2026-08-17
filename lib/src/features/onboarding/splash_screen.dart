import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../authentication/auth_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    final authService = AuthService();
    await authService.restoreSession();
    final isAuthenticated = authService.isAuthenticated();

    if (mounted) {
      if (isAuthenticated) {
        final prefs = await SharedPreferences.getInstance();
        if (!mounted) return;
        final profileOnboardingCompleted =
            prefs.getBool('onboarding_completed') ?? false;

        if (!profileOnboardingCompleted) {
          final currentUser = await authService.getCurrentUser();
          if (!mounted) return;

          final hasExistingProfile =
              currentUser != null &&
              currentUser.email.isNotEmpty &&
              currentUser.name.trim().isNotEmpty;

          if (hasExistingProfile) {
            await prefs.setBool('onboarding_completed', true);
          }
        }

        final shouldSkipOnboarding =
            prefs.getBool('onboarding_completed') ?? false;

        if (!mounted) return;

        if (shouldSkipOnboarding) {
          // Profile setup done, go to home
          context.go('/');
        } else {
          // Need to complete profile setup
          context.go('/onboarding');
        }
      } else {
        // User is not logged in, go to login
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // You can replace this with your app logo
            Icon(
              Icons.electric_car,
              size: 100,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'EVraahein',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
