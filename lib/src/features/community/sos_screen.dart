import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'sos_service.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../vehicle_profile/vehicle_provider.dart';

class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isSending = false;
  final _formKey = GlobalKey<FormState>();
  
  // Form Controllers
  final _carModelController = TextEditingController();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  double _currentSoc = 20;
  
  // Mock Location (In real app, use Geolocator)
  final double _latitude = 17.3850;
  final double _longitude = 78.4867;
  
  String? _selectedVehicleId;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
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
    
    // Auto-select first vehicle if available and none selected
    if (_selectedVehicleId == null && vehicles.isNotEmpty) {
      _selectedVehicleId = vehicles.first.id;
      _carModelController.text = '${vehicles.first.brand} ${vehicles.first.model}';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency SOS'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(PhosphorIcons.warning(PhosphorIconsStyle.duotone), size: 64, color: theme.colorScheme.error),
              const Gap(16),
              Text(
                'Request Assistance',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
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
                initialValue: '17.3850, 78.4867 (Current Location)',
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'GPS Location',
                  prefixIcon: Icon(Icons.location_on),
                  border: OutlineInputBorder(),
                ),
              ),
              const Gap(16),
              
              // Car Model (Dropdown or Text)
              if (vehicles.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _selectedVehicleId,
                  decoration: const InputDecoration(
                    labelText: 'Select Vehicle',
                    prefixIcon: Icon(Icons.directions_car),
                    border: OutlineInputBorder(),
                  ),
                  items: vehicles.map((v) {
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
                  validator: (value) => value == null || value.isEmpty ? 'Please enter car model' : null,
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
                validator: (value) => value == null || value.isEmpty ? 'Please enter phone number' : null,
              ),
              const Gap(16),

              // Custom Message
              TextFormField(
                controller: _messageController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message (Optional)',
                  hintText: 'Describe your issue (e.g., Flat tyre, Out of charge)',
                  prefixIcon: Icon(Icons.message),
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const Gap(24),
              
              // SOC Slider
              Text('Current SOC: ${_currentSoc.round()}%', style: theme.textTheme.titleMedium),
              Slider(
                value: _currentSoc,
                min: 0,
                max: 100,
                divisions: 100,
                label: _currentSoc.round().toString(),
                activeColor: _currentSoc < 20 ? theme.colorScheme.error : theme.colorScheme.primary,
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
                        color: _isSending ? Colors.grey : theme.colorScheme.error,
                        boxShadow: [
                          if (!_isSending)
                            BoxShadow(
                              color: theme.colorScheme.error.withValues(alpha: 0.4),
                              blurRadius: 10 + (_controller.value * 10),
                              spreadRadius: 2 + (_controller.value * 5),
                            ),
                        ],
                      ),
                      child: Center(
                        child: _isSending
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.sos, color: Colors.white, size: 32),
                                  const Gap(12),
                                  Text(
                                    'SEND ALERT',
                                    style: theme.textTheme.titleLarge?.copyWith(
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

    setState(() {
      _isSending = true;
    });

    try {
      final service = SosService();
      // TODO: Get actual user ID from Auth Provider
      const userId = "user_123"; 
      
      final result = await service.sendSosAlert(
        userId: userId,
        latitude: _latitude,
        longitude: _longitude,
        carModel: _carModelController.text,
        phoneNumber: _phoneController.text,
        message: _messageController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Success: ${result['message']} to ${result['users_notified']} users!'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send alert: $e'), backgroundColor: Colors.red),
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
}
