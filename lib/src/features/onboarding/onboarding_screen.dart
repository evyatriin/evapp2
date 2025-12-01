import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../authentication/user_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;

  // Step 1: Profile
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isPhoneVerified = false;

  // Step 2: Vehicle
  String? _selectedBrand;
  String? _selectedModel;
  String? _selectedConnector;

  // Step 3: Location
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill name if available
    final user = ref.read(userProvider);
    if (user != null) {
      _nameController.text = user.name;
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _verifyPhone() async {
    if (_phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a phone number')),
      );
      return;
    }

    // Mock OTP Flow
    final otpController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify Phone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the OTP sent to your phone (Mock: 123456)'),
            const Gap(16),
            TextField(
              controller: otpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'OTP',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (otpController.text == '123456') {
                setState(() {
                  _isPhoneVerified = true;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Phone verified successfully!')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid OTP')),
                );
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
        }
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are permanently denied, we cannot request permissions.')),
        );
      }
      return;
    }

    setState(() {
      _locationGranted = true;
    });
  }

  Future<void> _completeOnboarding() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(userProvider.notifier).completeOnboarding(
        phoneNumber: _phoneController.text,
        isPhoneVerified: _isPhoneVerified,
        vehicleDetails: {
          'brand': _selectedBrand,
          'model': _selectedModel,
          'connector': _selectedConnector,
        },
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);

      if (mounted) {
        context.go('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Disable swipe
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildProfileStep(),
                  _buildVehicleStep(),
                  _buildLocationStep(),
                ],
              ),
            ),
            // Bottom Navigation
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicators
                  Row(
                    children: List.generate(
                      3,
                      (index) => Container(
                        margin: const EdgeInsets.only(right: 8),
                        height: 8,
                        width: _currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  // Button
                  if (_currentPage == 2)
                    FilledButton(
                      onPressed: _isLoading ? null : _completeOnboarding,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Get Started'),
                    )
                  else
                    FilledButton.tonal(
                      onPressed: () {
                        // Validation logic
                        if (_currentPage == 0) {
                          if (_nameController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your name')));
                            return;
                          }
                          if (_phoneController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your phone number')));
                            return;
                          }
                          if (!_isPhoneVerified) {
                            // Allow proceeding but warn? Or just proceed.
                            // User requested: "If the user skips the phone verification..."
                            // So we just proceed.
                          }
                        } else if (_currentPage == 1) {
                           if (_selectedBrand == null || _selectedModel == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your vehicle')));
                            return;
                          }
                        }
                        _nextPage();
                      },
                      child: const Text('Next'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Gap(40),
          Icon(PhosphorIcons.userCircle(PhosphorIconsStyle.duotone), size: 64, color: Theme.of(context).colorScheme.primary),
          const Gap(24),
          Text(
            'Let\'s get to know you',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Gap(8),
          Text(
            'We need a few details to set up your profile.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const Gap(32),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const Gap(24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  onChanged: (_) => setState(() => _isPhoneVerified = false), // Reset verification on change
                ),
              ),
              const Gap(16),
              if (_isPhoneVerified)
                const Icon(Icons.check_circle, color: Colors.green, size: 32)
              else
                FilledButton(
                  onPressed: _verifyPhone,
                  child: const Text('Verify'),
                ),
                const Gap(8),
                TextButton(
                  onPressed: () {
                     // Just visual feedback or nothing, since "Next" button handles the flow
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone verification skipped')));
                  },
                  child: const Text('Skip'),
                ),
            ],
          ),
          if (_isPhoneVerified)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text('Phone verified', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }

  Widget _buildVehicleStep() {
    // Mock Data
    final brands = ['Tata', 'MG', 'Hyundai', 'Kia', 'Mahindra', 'BYD'];
    final models = {
      'Tata': ['Nexon EV', 'Tiago EV', 'Tigor EV', 'Punch EV'],
      'MG': ['ZS EV', 'Comet EV'],
      'Hyundai': ['Kona Electric', 'Ioniq 5'],
      'Kia': ['EV6'],
      'Mahindra': ['XUV400'],
      'BYD': ['Atto 3', 'E6'],
    };
    final connectors = ['CCS2', 'Type 2', 'CHAdeMO', 'GB/T'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Gap(40),
          Icon(PhosphorIcons.car(PhosphorIconsStyle.duotone), size: 64, color: Theme.of(context).colorScheme.primary),
          const Gap(24),
          Text(
            'Your Electric Vehicle',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Gap(8),
          Text(
            'Tell us about your car to help us plan better routes.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const Gap(32),
          DropdownButtonFormField<String>(
            value: _selectedBrand,
            decoration: const InputDecoration(
              labelText: 'Brand',
              border: OutlineInputBorder(),
            ),
            items: brands.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
            onChanged: (value) {
              setState(() {
                _selectedBrand = value;
                _selectedModel = null; // Reset model
              });
            },
          ),
          const Gap(24),
          DropdownButtonFormField<String>(
            value: _selectedModel,
            decoration: const InputDecoration(
              labelText: 'Model',
              border: OutlineInputBorder(),
            ),
            items: (_selectedBrand != null ? models[_selectedBrand] ?? [] : [])
                .map((m) => DropdownMenuItem<String>(value: m, child: Text(m)))
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedModel = value;
              });
            },
          ),
          const Gap(24),
          DropdownButtonFormField<String>(
            value: _selectedConnector,
            decoration: const InputDecoration(
              labelText: 'Connector Type',
              border: OutlineInputBorder(),
            ),
            items: connectors.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (value) {
              setState(() {
                _selectedConnector = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.duotone), size: 80, color: Theme.of(context).colorScheme.primary),
          const Gap(32),
          Text(
            'Enable Location',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const Gap(16),
          Text(
            'We need your location to find nearby charging stations and plan routes from your current position.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const Gap(48),
          if (_locationGranted)
            const Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 64),
                Gap(8),
                Text('Location Access Granted!', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            )
          else
            FilledButton.icon(
              onPressed: _requestLocation,
              icon: const Icon(Icons.location_on),
              label: const Text('Grant Location Access'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
        ],
      ),
    );
  }
}
