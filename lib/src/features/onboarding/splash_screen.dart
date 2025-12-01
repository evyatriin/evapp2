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
    // Add a small delay to show the splash screen
    await Future.delayed(const Duration(seconds: 2));
    
    // Check authentication status
    final authService = AuthService();
    final isAuthenticated = authService.isAuthenticated();
    
    if (mounted) {
      if (isAuthenticated) {
        // User is logged in, go to home
        context.go('/');
      } else {
        // User is not logged in, check onboarding
        final prefs = await SharedPreferences.getInstance();
        final onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
        
        if (onboardingCompleted) {
          context.go('/login');
        } else {
          context.go('/onboarding');
        }
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
              'EV-Ranger',
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
