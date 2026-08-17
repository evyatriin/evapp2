import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'sos_service.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../authentication/user_provider.dart';
import '../authentication/verification_gate.dart';
import '../vehicle_profile/vehicle_provider.dart';

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isSending = false;
  final _formKey = GlobalKey<FormState>();

  // Form Controllers
  final _carModelController = TextEditingController();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  double _currentSoc = 20;

  Position? _currentPosition;
  bool _isResolvingLocation = true;

  String? _selectedVehicleId;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _resolveCurrentLocation();
  }

  @override
  void dispose() {
    _controller.dispose();
    _carModelController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vehicles = ref.watch(vehicleProvider);
    final user = ref.watch(userProvider);

    // Double-verification gate — SOS needs a confirmed email + phone so nearby
    // drivers can trust and reach the sender. Backend enforces this too.
    if (user != null && !user.isDoubleVerified) {
      return Scaffold(
        appBar: AppBar(title: const Text('Emergency SOS'), centerTitle: true),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                PhosphorIcons.shieldWarning(PhosphorIconsStyle.duotone),
                size: 72,
                color: theme.colorScheme.error,
              ),
              const Gap(20),
              Text(
                'Verify to send an SOS',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Gap(12),
              Text(
                'SOS alerts go out to nearby drivers, who need to trust and reach you. Verify your email and phone to unlock emergency alerts.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const Gap(28),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await ensureVerifiedForHelp(
                    context,
                    ref,
                    action: 'send an SOS',
                  );
                  if (ok && mounted) setState(() {});
                },
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Verify now'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Auto-select first vehicle if available and none selected
    if (_selectedVehicleId == null && vehicles.isNotEmpty) {
      _selectedVehicleId = vehicles.first.id;
      _carModelController.text =
          '${vehicles.first.brand} ${vehicles.first.model}';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Emergency SOS'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                PhosphorIcons.warning(PhosphorIconsStyle.duotone),
                size: 64,
                color: theme.colorScheme.error,
              ),
              const Gap(16),
              Text(
                'Request Assistance',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Gap(8),
              Text(
                'Provide details to alert nearby EV owners (15-20km radius).',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const Gap(32),

              // Location (Read-only for now)
              TextFormField(
                initialValue: _locationLabel(),
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'GPS Location',
                  prefixIcon: const Icon(Icons.location_on),
                  suffixIcon:
                      _isResolvingLocation
                          ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                          : IconButton(
                            onPressed: _resolveCurrentLocation,
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Refresh location',
                          ),
                ),
              ),
              const Gap(16),

              // Car Model (Dropdown or Text)
              if (vehicles.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _selectedVehicleId,
                  decoration: const InputDecoration(
                    labelText: 'Select Vehicle',
                    prefixIcon: Icon(Icons.directions_car),
                    border: OutlineInputBorder(),
                  ),
                  items:
                      vehicles.map((v) {
                        return DropdownMenuItem(
                          value: v.id,
                          child: Text('${v.brand} ${v.model} ${v.variant}'),
                        );
                      }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedVehicleId = value;
                      final v = vehicles.firstWhere((v) => v.id == value);
                      _carModelController.text = '${v.brand} ${v.model}';
                    });
                  },
                )
              else
                TextFormField(
                  controller: _carModelController,
                  decoration: const InputDecoration(
                    labelText: 'Car Model',
                    hintText: 'e.g. Tata Nexon EV',
                    prefixIcon: Icon(Icons.directions_car),
                    border: OutlineInputBorder(),
                  ),
                  validator:
                      (value) =>
                          value == null || value.isEmpty
                              ? 'Please enter car model'
                              : null,
                ),
              const Gap(16),

              // Phone Number
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                validator:
                    (value) =>
                        value == null || value.isEmpty
                            ? 'Please enter phone number'
                            : null,
              ),
              const Gap(16),

              // Custom Message
              TextFormField(
                controller: _messageController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message (Optional)',
                  hintText:
                      'Describe your issue (e.g., Flat tyre, Out of charge)',
                  prefixIcon: Icon(Icons.message),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const Gap(24),

              // SOC Slider
              Text(
                'Current SOC: ${_currentSoc.round()}%',
                style: theme.textTheme.titleMedium,
              ),
              Slider(
                value: _currentSoc,
                min: 0,
                max: 100,
                divisions: 100,
                label: _currentSoc.round().toString(),
                activeColor:
                    _currentSoc < 20
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                onChanged: (value) => setState(() => _currentSoc = value),
              ),

              const Gap(32),

              // SOS Button
              GestureDetector(
                onTap: _isSending ? null : _handleSosPress,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Container(
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(40),
                        color:
                            _isSending ? Colors.grey : theme.colorScheme.error,
                        boxShadow: [
                          if (!_isSending)
                            BoxShadow(
                              color: theme.colorScheme.error.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 10 + (_controller.value * 10),
                              spreadRadius: 2 + (_controller.value * 5),
                            ),
                        ],
                      ),
                      child: Center(
                        child:
                            _isSending
                                ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                                : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.sos,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    const Gap(12),
                                    Text(
                                      'SEND ALERT',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSosPress() async {
    if (!_formKey.currentState!.validate()) return;
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current location is required before sending SOS'),
        ),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final service = SosService();
      final userId = ref.read(userProvider)?.id;
      if (userId == null) {
        throw Exception('Please log in before sending an SOS alert');
      }

      final result = await service.sendSosAlert(
        userId: userId,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        carModel: _carModelController.text,
        phoneNumber: _phoneController.text,
        message: _messageController.text,
      );

      if (mounted) {
        if (result.wasSent) {
          final data = result.alertData ?? {};
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Alert sent to ${data['users_notified'] ?? 'nearby'} users!',
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
              duration: const Duration(seconds: 4),
            ),
          );
          Navigator.pop(context);
        } else {
          // Queued — user is offline
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "You're offline — SOS queued and will send when you're back online.",
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 5),
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send alert: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  String _locationLabel() {
    if (_currentPosition == null) {
      return _isResolvingLocation
          ? 'Resolving current location...'
          : 'Location unavailable. Refresh and try again.';
    }
    return '${_currentPosition!.latitude.toStringAsFixed(5)}, ${_currentPosition!.longitude.toStringAsFixed(5)}';
  }

  Future<void> _resolveCurrentLocation() async {
    setState(() {
      _isResolvingLocation = true;
    });

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is required to send an SOS alert');
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled on this device');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingLocation = false;
        });
      }
    }
  }

}
