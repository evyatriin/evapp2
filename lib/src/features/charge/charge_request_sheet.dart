import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../authentication/user_provider.dart';
import '../mapping/station_model.dart';
import '../vehicle_profile/vehicle_provider.dart';
import 'charging_service.dart';

class ChargeRequestSheet extends ConsumerStatefulWidget {
  final StationModel station;

  const ChargeRequestSheet({super.key, required this.station});

  @override
  ConsumerState<ChargeRequestSheet> createState() => _ChargeRequestSheetState();
}

class _ChargeRequestSheetState extends ConsumerState<ChargeRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _service = ChargingService();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  final _vehicleController = TextEditingController();
  int _currentSoc = 20;
  bool _isSubmitting = false;
  late DateTime _requestedStartAt;

  @override
  void initState() {
    super.initState();
    _requestedStartAt = DateTime.now().add(const Duration(minutes: 30));
    final vehicles = ref.read(vehicleProvider);
    if (vehicles.isNotEmpty) {
      final vehicle = vehicles.first;
      _vehicleController.text = '${vehicle.brand} ${vehicle.model}';
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _messageController.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  Future<void> _pickRequestedStartAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _requestedStartAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_requestedStartAt),
    );
    if (time == null || !mounted) return;

    setState(() {
      _requestedStartAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(userProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to request charging.')),
      );
      return;
    }

    final stationRecordId = widget.station.stationRecordId;
    if (stationRecordId == null || stationRecordId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This hosted charger is missing its request record. Try again after refreshing the map.',
          ),
        ),
      );
      return;
    }
    if (_requestedStartAt.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a future start time for the request.'),
        ),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _service.createChargerRequest(
        stationId: stationRecordId,
        requesterUserId: user.id,
        requesterName: user.name,
        requesterPhone: _phoneController.text.trim(),
        vehicleName: _vehicleController.text.trim().isEmpty
            ? null
            : _vehicleController.text.trim(),
        currentSoc: _currentSoc,
        message: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
        requestedStartAt: _requestedStartAt,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send request: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final station = widget.station;
    final availabilityBits = <String>[
      if ((station.availableHours ?? '').isNotEmpty) station.availableHours!,
      if (station.availableDays.isNotEmpty) station.availableDays.join(', '),
      if ((station.availableFrom ?? '').isNotEmpty ||
          (station.availableTo ?? '').isNotEmpty)
        '${station.availableFrom ?? '--'} - ${station.availableTo ?? '--'}',
    ];
    final trustIndicators = <String>[
      if (station.verificationBadges['phone_verified'] == true) 'Phone verified',
      if (station.verificationBadges['charger_photo_uploaded'] == true)
        'Charger photo uploaded',
      if (station.verificationBadges['parking_photo_uploaded'] == true)
        'Parking photo uploaded',
      if (station.verificationBadges['responsive_host'] == true) 'Responsive host',
      if (station.verificationBadges['repeat_host'] == true) 'Repeat host',
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Request Charging Access',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(8),
              Text(
                station.name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const Gap(10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'This is a privately hosted charger shared by an individual host. Verify connector compatibility, parking suitability, and availability before arrival.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Gap(12),
              if (station.pricePerKwh != null || station.pricePerSession != null)
                Text(
                  [
                    if (station.pricePerKwh != null)
                      'Suggested energy access ₹${station.pricePerKwh!.toStringAsFixed(0)}/kWh',
                    if (station.pricePerSession != null)
                      'Session amount ₹${station.pricePerSession!.toStringAsFixed(0)}',
                  ].join(' • '),
                ),
              if (availabilityBits.isNotEmpty) ...[
                const Gap(6),
                Text(
                  'Availability: ${availabilityBits.join(' • ')}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if ((station.visitorAccessType ?? '').isNotEmpty) ...[
                const Gap(6),
                Text(
                  'Visitor access: ${station.visitorAccessType}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (trustIndicators.isNotEmpty) ...[
                const Gap(10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: trustIndicators
                      .map(
                        (label) => Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(label),
                        ),
                      )
                      .toList(),
                ),
              ],
              const Gap(16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Your phone number',
                ),
                keyboardType: TextInputType.phone,
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const Gap(12),
              TextFormField(
                controller: _vehicleController,
                decoration: const InputDecoration(
                  labelText: 'Vehicle (optional)',
                ),
              ),
              const Gap(12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Preferred start time'),
                subtitle: Text(
                  DateFormat('dd MMM yyyy, hh:mm a').format(_requestedStartAt),
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _pickRequestedStartAt,
              ),
              const Gap(8),
              Text(
                'Current SOC: $_currentSoc%',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Slider(
                value: _currentSoc.toDouble(),
                min: 0,
                max: 100,
                divisions: 100,
                label: '$_currentSoc%',
                onChanged: (value) {
                  setState(() {
                    _currentSoc = value.round();
                  });
                },
              ),
              const Gap(8),
              TextFormField(
                controller: _messageController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Message to host (optional)',
                  hintText: 'Share ETA or anything the host should know',
                ),
              ),
              const Gap(16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Access Request'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
