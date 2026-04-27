import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../authentication/user_provider.dart';
import 'charging_service.dart';

class CommunityChargingScreen extends ConsumerStatefulWidget {
  const CommunityChargingScreen({super.key});

  @override
  ConsumerState<CommunityChargingScreen> createState() =>
      _CommunityChargingScreenState();
}

class _CommunityChargingScreenState
    extends ConsumerState<CommunityChargingScreen> {
  final ChargingService _chargingService = ChargingService();

  bool _isLoading = true;
  List<HostChargerListing> _hostedChargers = const [];
  List<ChargerRequestItem> _incomingRequests = const [];
  List<ChargerRequestItem> _outgoingRequests = const [];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadData);
  }

  Future<void> _loadData() async {
    final user = ref.read(userProvider);
    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final hostedFuture = _chargingService.getHostedChargers(user.id);
    final incomingFuture = _chargingService.getIncomingRequests(user.id);
    final outgoingFuture = _chargingService.getOutgoingRequests(user.id);

    try {
      final results = await Future.wait([
        hostedFuture,
        incomingFuture,
        outgoingFuture,
      ]);

      if (!mounted) return;
      setState(() {
        _hostedChargers = results[0] as List<HostChargerListing>;
        _incomingRequests = results[1] as List<ChargerRequestItem>;
        _outgoingRequests = results[2] as List<ChargerRequestItem>;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load community charging data: $error')),
      );
    }
  }

  Future<void> _openHostedChargerForm([HostChargerListing? listing]) async {
    final user = ref.read(userProvider);
    if (user == null) return;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _HostedChargerFormSheet(
        existing: listing,
        ownerId: user.id,
        defaultHostName: user.name,
      ),
    );

    if (saved == true) {
      await _loadData();
    }
  }

  Future<void> _updateRequestStatus(
    ChargerRequestItem item,
    String status,
  ) async {
    final user = ref.read(userProvider);
    if (user == null) return;

    try {
      if (status == 'completed') {
        await _chargingService.completeChargerRequest(
          requestId: item.id,
          hostUserId: user.id,
        );
      } else {
        await _chargingService.decideChargerRequest(
          requestId: item.id,
          hostUserId: user.id,
          status: status,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'accepted'
                  ? 'Request accepted.'
                  : status == 'rejected'
                  ? 'Request rejected.'
                  : 'Request marked completed.',
            ),
          ),
        );
      }
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update request: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Community Charging'),
      ),
      floatingActionButton: user == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openHostedChargerForm(),
              icon: const Icon(Icons.add_home_work_outlined),
              label: const Text('Host Charger'),
            ),
      body: user == null
          ? const Center(child: Text('Please login to host or request charging.'))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Host your home or community charger',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Gap(8),
                          Text(
                            'List your charger, set a manual rate, and accept requests. Payment stays manual by UPI or cash for this first release.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Gap(16),
                  _SectionHeader(
                    title: 'My Hosted Chargers',
                    actionLabel: 'Add',
                    onAction: () => _openHostedChargerForm(),
                  ),
                  const Gap(8),
                  if (_isLoading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_hostedChargers.isEmpty)
                    const _EmptyCard(
                      message:
                          'No hosted chargers yet. Add one to start receiving local charging requests.',
                    )
                  else
                    ..._hostedChargers.map(
                      (listing) => _HostedChargerCard(
                        listing: listing,
                        onEdit: () => _openHostedChargerForm(listing),
                      ),
                    ),
                  const Gap(16),
                  _SectionHeader(title: 'Incoming Requests'),
                  const Gap(8),
                  if (_isLoading)
                    const SizedBox.shrink()
                  else if (_incomingRequests.isEmpty)
                    const _EmptyCard(
                      message:
                          'Incoming requests will appear here when drivers request charging from your hosted charger.',
                    )
                  else
                    ..._incomingRequests.map(
                      (item) => _RequestCard(
                        item: item,
                        showHostContact: false,
                        onAccept: item.status == 'pending'
                            ? () => _updateRequestStatus(item, 'accepted')
                            : null,
                        onReject: item.status == 'pending'
                            ? () => _updateRequestStatus(item, 'rejected')
                            : null,
                        onComplete: item.status == 'accepted'
                            ? () => _updateRequestStatus(item, 'completed')
                            : null,
                      ),
                    ),
                  const Gap(16),
                  _SectionHeader(title: 'My Outgoing Requests'),
                  const Gap(8),
                  if (_isLoading)
                    const SizedBox.shrink()
                  else if (_outgoingRequests.isEmpty)
                    const _EmptyCard(
                      message:
                          'Your sent requests will show up here, including host contact details after acceptance.',
                    )
                  else
                    ..._outgoingRequests.map(
                      (item) => _RequestCard(
                        item: item,
                        showHostContact: true,
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _HostedChargerFormSheet extends StatefulWidget {
  final HostChargerListing? existing;
  final String ownerId;
  final String defaultHostName;

  const _HostedChargerFormSheet({
    required this.ownerId,
    required this.defaultHostName,
    this.existing,
  });

  @override
  State<_HostedChargerFormSheet> createState() => _HostedChargerFormSheetState();
}

class _HostedChargerFormSheetState extends State<_HostedChargerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _service = ChargingService();

  late final TextEditingController _nameController;
  late final TextEditingController _addressController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late final TextEditingController _hostNameController;
  late final TextEditingController _hostPhoneController;
  late final TextEditingController _hostUpiController;
  late final TextEditingController _connectorTypesController;
  late final TextEditingController _powerKwController;
  late final TextEditingController _pricePerKwhController;
  late final TextEditingController _pricePerSessionController;
  late final TextEditingController _availableFromController;
  late final TextEditingController _availableToController;
  late final TextEditingController _availableDaysController;
  late final TextEditingController _accessInstructionsController;
  late final TextEditingController _parkingNotesController;
  late final TextEditingController _houseRulesController;
  bool _isAcceptingRequests = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final listing = widget.existing;
    _nameController = TextEditingController(text: listing?.name ?? '');
    _addressController = TextEditingController(text: listing?.address ?? '');
    _latitudeController = TextEditingController(
      text: listing != null ? listing.latitude.toString() : '',
    );
    _longitudeController = TextEditingController(
      text: listing != null ? listing.longitude.toString() : '',
    );
    _hostNameController = TextEditingController(
      text: listing?.hostName.isNotEmpty == true
          ? listing!.hostName
          : widget.defaultHostName,
    );
    _hostPhoneController = TextEditingController(text: listing?.hostPhone ?? '');
    _hostUpiController = TextEditingController(text: listing?.hostUpiId ?? '');
    _connectorTypesController = TextEditingController(
      text: listing?.connectorTypes.join(', ') ?? '',
    );
    _powerKwController = TextEditingController(
      text: listing?.powerKw?.toString() ?? '',
    );
    _pricePerKwhController = TextEditingController(
      text: listing?.pricePerKwh?.toString() ?? '',
    );
    _pricePerSessionController = TextEditingController(
      text: listing?.pricePerSession?.toString() ?? '',
    );
    _availableFromController = TextEditingController(
      text: listing?.availableFrom ?? '',
    );
    _availableToController = TextEditingController(
      text: listing?.availableTo ?? '',
    );
    _availableDaysController = TextEditingController(
      text: listing?.availableDays.join(', ') ?? '',
    );
    _accessInstructionsController = TextEditingController(
      text: listing?.accessInstructions ?? '',
    );
    _parkingNotesController = TextEditingController(
      text: listing?.parkingNotes ?? '',
    );
    _houseRulesController = TextEditingController(
      text: listing?.houseRules ?? '',
    );
    _isAcceptingRequests = listing?.isAcceptingRequests ?? true;

    if (listing == null) {
      Future<void>.microtask(_useCurrentLocation);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _hostNameController.dispose();
    _hostPhoneController.dispose();
    _hostUpiController.dispose();
    _connectorTypesController.dispose();
    _powerKwController.dispose();
    _pricePerKwhController.dispose();
    _pricePerSessionController.dispose();
    _availableFromController.dispose();
    _availableToController.dispose();
    _availableDaysController.dispose();
    _accessInstructionsController.dispose();
    _parkingNotesController.dispose();
    _houseRulesController.dispose();
    super.dispose();
  }

  double? _parseDouble(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  String? _validateOptionalNumber(
    String? value, {
    bool allowZero = false,
  }) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parsed = double.tryParse(trimmed);
    if (parsed == null) {
      return 'Enter a valid number';
    }
    if (!allowZero && parsed <= 0) {
      return 'Enter a value greater than 0';
    }
    if (allowZero && parsed < 0) {
      return 'Enter 0 or more';
    }
    return null;
  }

  List<String> _splitCsv(String value) {
    return value
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<void> _useCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is required');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not use current location: $error')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid latitude and longitude.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      await _service.saveHostedCharger(
        stationId: widget.existing?.id,
        ownerId: widget.ownerId,
        name: _nameController.text.trim(),
        latitude: latitude,
        longitude: longitude,
        address: _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        connectorTypes: _splitCsv(_connectorTypesController.text),
        powerKw: _parseDouble(_powerKwController.text),
        pricePerKwh: _parseDouble(_pricePerKwhController.text),
        pricePerSession: _parseDouble(_pricePerSessionController.text),
        hostName: _hostNameController.text.trim().isEmpty
            ? widget.defaultHostName.isEmpty
                ? 'Community Host'
                : widget.defaultHostName
            : _hostNameController.text.trim(),
        hostPhone: _hostPhoneController.text.trim(),
        hostUpiId: _hostUpiController.text.trim().isEmpty
            ? null
            : _hostUpiController.text.trim(),
        accessInstructions: _accessInstructionsController.text.trim().isEmpty
            ? null
            : _accessInstructionsController.text.trim(),
        availableFrom: _availableFromController.text.trim().isEmpty
            ? null
            : _availableFromController.text.trim(),
        availableTo: _availableToController.text.trim().isEmpty
            ? null
            : _availableToController.text.trim(),
        availableDays: _splitCsv(_availableDaysController.text),
        parkingNotes: _parkingNotesController.text.trim().isEmpty
            ? null
            : _parkingNotesController.text.trim(),
        houseRules: _houseRulesController.text.trim().isEmpty
            ? null
            : _houseRulesController.text.trim(),
        isAcceptingRequests: _isAcceptingRequests,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save hosted charger: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing == null ? 'Host Charger' : 'Edit Hosted Charger',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(16),
              Text(
                'Keep this launch listing light: name, location, phone, connector, rate, and one short note are enough to go live.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Listing name'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required' : null,
              ),
              const Gap(12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const Gap(12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.my_location),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        _latitudeController.text.trim().isEmpty ||
                                _longitudeController.text.trim().isEmpty
                            ? 'Use your current location for the charger pin'
                            : 'Pin set at ${_latitudeController.text.trim()}, ${_longitudeController.text.trim()}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _useCurrentLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Use current location'),
                ),
              ),
              const Gap(12),
              TextFormField(
                controller: _hostPhoneController,
                decoration: const InputDecoration(labelText: 'Host phone'),
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Required'
                    : null,
              ),
              const Gap(12),
              TextFormField(
                controller: _hostUpiController,
                decoration: const InputDecoration(
                  labelText: 'UPI ID (optional)',
                ),
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _connectorTypesController,
                      decoration: const InputDecoration(
                        labelText: 'Connectors',
                        hintText: 'CCS2, Type 2',
                      ),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: TextFormField(
                      controller: _powerKwController,
                      decoration: const InputDecoration(
                        labelText: 'Power in kW (optional)',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) => _validateOptionalNumber(value),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: TextFormField(
                      controller: _pricePerSessionController,
                      decoration: const InputDecoration(
                        labelText: 'Price per session',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) => _validateOptionalNumber(value),
                    ),
                  ),
                ],
              ),
              const Gap(12),
              TextFormField(
                controller: _pricePerKwhController,
                decoration: const InputDecoration(
                  labelText: 'Price per kWh (optional)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) => _validateOptionalNumber(value),
              ),
              const Gap(12),
              TextFormField(
                controller: _accessInstructionsController,
                decoration: const InputDecoration(
                  labelText: 'Arrival notes',
                  hintText: 'Gate, landmark, parking cue, or what drivers should know',
                ),
                maxLines: 3,
              ),
              const Gap(12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Accept charging requests'),
                value: _isAcceptingRequests,
                onChanged: (value) {
                  setState(() {
                    _isAcceptingRequests = value;
                  });
                },
              ),
              const Gap(8),
              Text(
                'Recommendation: add charger and parking photos next. They help trust and can later be used to auto-fill listing details, but I am not forcing them in this MVP form.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Gap(16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save hosted charger'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostedChargerCard extends StatelessWidget {
  final HostChargerListing listing;
  final VoidCallback onEdit;

  const _HostedChargerCard({
    required this.listing,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleBits = <String>[
      if (listing.pricePerKwh != null)
        'Rs ${listing.pricePerKwh!.toStringAsFixed(0)}/kWh',
      if (listing.pricePerSession != null)
        'Rs ${listing.pricePerSession!.toStringAsFixed(0)}/session',
      if (listing.availableDays.isNotEmpty) listing.availableDays.join(', '),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    listing.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.tonal(
                  onPressed: onEdit,
                  child: const Text('Edit'),
                ),
              ],
            ),
            const Gap(8),
            if ((listing.address ?? '').isNotEmpty)
              Text(
                listing.address!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (subtitleBits.isNotEmpty) ...[
              const Gap(8),
              Text(subtitleBits.join(' • ')),
            ],
            const Gap(8),
            Text(
              listing.isAcceptingRequests
                  ? 'Accepting requests'
                  : 'Requests paused',
              style: theme.textTheme.bodySmall?.copyWith(
                color: listing.isAcceptingRequests
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final ChargerRequestItem item;
  final bool showHostContact;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final VoidCallback? onComplete;

  const _RequestCard({
    required this.item,
    required this.showHostContact,
    this.onAccept,
    this.onReject,
    this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stationName =
        item.station?['name']?.toString() ?? 'Hosted Charger';
    final when = item.requestedStartAt == null
        ? 'Time not set'
        : DateFormat('dd MMM, hh:mm a').format(item.requestedStartAt!.toLocal());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stationName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                _StatusChip(status: item.status),
              ],
            ),
            const Gap(8),
            Text('Requested for: $when'),
            if ((item.requesterName ?? '').isNotEmpty) ...[
              const Gap(4),
              Text('Requester: ${item.requesterName}'),
            ],
            if ((item.requesterPhone ?? '').isNotEmpty) ...[
              const Gap(4),
              Text('Phone: ${item.requesterPhone}'),
            ],
            if ((item.vehicleName ?? '').isNotEmpty) ...[
              const Gap(4),
              Text('Vehicle: ${item.vehicleName}'),
            ],
            if (item.currentSoc != null) ...[
              const Gap(4),
              Text('SOC: ${item.currentSoc}%'),
            ],
            if ((item.message ?? '').isNotEmpty) ...[
              const Gap(8),
              Text(item.message!),
            ],
            if (item.estimatedAmount != null) ...[
              const Gap(8),
              Text(
                'Estimated amount: Rs ${item.estimatedAmount!.toStringAsFixed(0)}',
              ),
            ],
            if (showHostContact && item.status == 'accepted') ...[
              const Gap(12),
              Text(
                'Host contact',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(6),
              if ((item.hostContact?['host_name'] ?? '').toString().isNotEmpty)
                Text('Host: ${item.hostContact?['host_name']}'),
              if ((item.hostContact?['host_phone'] ?? '').toString().isNotEmpty)
                Text('Phone: ${item.hostContact?['host_phone']}'),
              if ((item.hostContact?['host_upi_id'] ?? '').toString().isNotEmpty)
                Text('UPI: ${item.hostContact?['host_upi_id']}'),
            ],
            if (onAccept != null || onReject != null || onComplete != null) ...[
              const Gap(12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onAccept != null)
                    FilledButton(
                      onPressed: onAccept,
                      child: const Text('Accept'),
                    ),
                  if (onReject != null)
                    OutlinedButton(
                      onPressed: onReject,
                      child: const Text('Reject'),
                    ),
                  if (onComplete != null)
                    FilledButton.tonal(
                      onPressed: onComplete,
                      child: const Text('Mark Complete'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (status) {
      'accepted' => theme.colorScheme.primary,
      'completed' => Colors.green,
      'rejected' => theme.colorScheme.error,
      'cancelled' => theme.colorScheme.error,
      _ => Colors.orange,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;

  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message),
      ),
    );
  }
}
