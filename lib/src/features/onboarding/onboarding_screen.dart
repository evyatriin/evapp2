import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../authentication/user_provider.dart';
import '../vehicle_profile/vehicle_provider.dart';

/// A value-first onboarding flow:
///   1. Welcome — what the app does and why it's worth it.
///   2. Add your EV — powers accurate range & charger matching (skippable).
///   3. Location — find chargers near you (skippable, with a settings fallback).
///
/// Every step can be skipped so a new user is never trapped, and the whole
/// flow can be dismissed with "Skip" from the top bar.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _lastPage = 2;

  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isFinishing = false;

  bool _locationGranted = false;
  bool _locationPermanentlyDenied = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
    );
  }

  void _nextPage() => _goToPage(_currentPage + 1);

  Future<void> _requestLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return;

    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationPermanentlyDenied = true);
      return;
    }

    if (permission == LocationPermission.denied) {
      // User declined this time — they can still continue and grant later.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No problem — you can enable location later from the map.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _locationGranted = true;
      _locationPermanentlyDenied = false;
    });
  }

  Future<void> _finish() async {
    if (_isFinishing) return;
    setState(() => _isFinishing = true);
    try {
      final user = ref.read(userProvider);
      if (user != null) {
        // Best-effort profile flag; never block finishing on a network hiccup.
        try {
          await ref.read(userProvider.notifier).completeOnboarding(
                phoneNumber: '',
                isPhoneVerified: false,
                vehicleDetails: {},
              );
        } catch (_) {
          // Non-fatal — the local flag below still lets the user in.
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);

      if (mounted) context.go('/');
    } finally {
      if (mounted) setState(() => _isFinishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep auth alive and react to a vehicle being added on step 2.
    ref.watch(userProvider);
    final hasVehicle = ref.watch(vehicleProvider).isNotEmpty;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top bar: progress dots + Skip.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
              child: Row(
                children: [
                  Row(
                    children: List.generate(
                      _lastPage + 1,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_currentPage != _lastPage)
                    TextButton(
                      onPressed: _isFinishing ? null : _finish,
                      child: const Text('Skip'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) =>
                    setState(() => _currentPage = index),
                children: [
                  _WelcomeStep(),
                  _VehicleStep(hasVehicle: hasVehicle),
                  _LocationStep(
                    granted: _locationGranted,
                    permanentlyDenied: _locationPermanentlyDenied,
                    onOpenSettings: Geolocator.openAppSettings,
                  ),
                ],
              ),
            ),
            _buildPrimaryAction(hasVehicle),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryAction(bool hasVehicle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: switch (_currentPage) {
        0 => FilledButton(
            onPressed: _nextPage,
            child: const Text('Get started'),
          ),
        1 => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: _isFinishing
                    ? null
                    : hasVehicle
                        ? _nextPage
                        : () => context.push('/onboarding/vehicle-select'),
                child: Text(hasVehicle ? 'Continue' : 'Choose your EV'),
              ),
              if (!hasVehicle)
                TextButton(
                  onPressed: _nextPage,
                  child: const Text("I'll add it later"),
                ),
            ],
          ),
        _ => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: _isFinishing
                    ? null
                    : _locationGranted
                        ? _finish
                        : _requestLocation,
                child: _isFinishing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_locationGranted ? 'Finish' : 'Enable location'),
              ),
              if (!_locationGranted)
                TextButton(
                  onPressed: _isFinishing ? null : _finish,
                  child: const Text('Skip for now'),
                ),
            ],
          ),
      },
    );
  }
}

/// Reusable icon + title + subtitle row used on the welcome step.
class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const Gap(16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Gap(2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Gap(16),
          Icon(
            PhosphorIcons.lightning(PhosphorIconsStyle.duotone),
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const Gap(20),
          Text(
            'Drive electric,\nwithout the range anxiety.',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              height: 1.15,
            ),
          ),
          const Gap(8),
          Text(
            "Here's what EVraahein does for you:",
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(24),
          _Benefit(
            icon: PhosphorIcons.path(PhosphorIconsStyle.duotone),
            title: 'Plan trips around your battery',
            subtitle:
                'Range, charging stops and elevation, all worked out for you.',
          ),
          _Benefit(
            icon: PhosphorIcons.mapPin(PhosphorIconsStyle.duotone),
            title: 'Find & rate live chargers',
            subtitle: "See what's working nearby, powered by the community.",
          ),
          _Benefit(
            icon: PhosphorIcons.gauge(PhosphorIconsStyle.duotone),
            title: 'Know your car in real time',
            subtitle: 'Connect over OBD for live battery and range data.',
          ),
          const Gap(16),
        ],
      ),
    );
  }
}

class _VehicleStep extends StatelessWidget {
  const _VehicleStep({required this.hasVehicle});

  final bool hasVehicle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIcons.car(PhosphorIconsStyle.duotone),
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const Gap(20),
          Text(
            'Add your EV',
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Gap(8),
          Text(
            'We use your car to calculate accurate range and only show '
            'chargers it can actually use. You can add more cars later.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Gap(28),
          if (hasVehicle)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.primary, size: 28),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      'Your EV is set. You can tweak the details anytime in '
                      'your profile.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LocationStep extends StatelessWidget {
  const _LocationStep({
    required this.granted,
    required this.permanentlyDenied,
    required this.onOpenSettings,
  });

  final bool granted;
  final bool permanentlyDenied;
  final Future<bool> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIcons.mapPin(PhosphorIconsStyle.duotone),
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const Gap(24),
          Text(
            'Find chargers near you',
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const Gap(12),
          Text(
            'Allow location so we can center the map on you and plan routes '
            'from where you are.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const Gap(32),
          if (granted)
            Column(
              children: [
                Icon(Icons.check_circle,
                    color: theme.colorScheme.primary, size: 56),
                const Gap(8),
                Text(
                  'Location enabled',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          else if (permanentlyDenied)
            Column(
              children: [
                Text(
                  'Location is turned off for EVraahein. Enable it in '
                  'Settings to use nearby chargers.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const Gap(12),
                OutlinedButton.icon(
                  onPressed: () => onOpenSettings(),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open Settings'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
