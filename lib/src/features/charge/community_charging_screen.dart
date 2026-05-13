import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../authentication/user_provider.dart';
import 'charging_service.dart';

const List<String> _propertyTypeOptions = [
  'Independent house',
  'Farmhouse',
  'Shop/commercial space',
  'Homestay/resort',
  'Office parking',
  'Apartment/society parking',
  'Other',
];

const List<String> _visitorAccessOptions = [
  'Open access',
  'Call before arrival',
  'Security gate approval needed',
  'Host must be present',
];

const List<String> _vehicleSizeOptions = [
  'Hatchback',
  'Sedan',
  'SUV',
  'Large SUV/MUV',
];

const Map<String, String> _locationAccessLabels = {
  'accessible_without_gated_approval':
      'Charger is accessible without gated community approval',
  'parking_available_for_visiting_evs':
      'Parking is available for visiting EVs',
  'above_ground_and_well_ventilated':
      'Charger is above ground and well ventilated',
  'reachable_by_standard_ev_cars':
      'Location is reachable by standard EV cars',
  'cable_does_not_block_public_roads':
      'Charging cable does not block public roads',
  'safe_access_after_sunset': 'Safe access available after sunset',
};

const Map<String, String> _safetyChecklistLabels = {
  'properly_earthed': 'Charger is properly earthed',
  'mcb_or_rccb_installed': 'MCB/RCCB protection is installed',
  'no_loose_extension_wiring': 'No loose extension wiring is used',
  'protected_from_rain_or_water': 'Charger is protected from rain/water exposure',
  'fire_extinguisher_available': 'Fire extinguisher available nearby',
};

const Map<String, String> _hostDeclarationLabels = {
  'complies_with_local_rules_and_safe_for_temporary_access':
      'I confirm this listing complies with local housing/community rules and is safe for temporary EV charging access.',
  'host_responsible_for_safety_access_and_electrical_compliance':
      'I understand I am responsible for maintaining charger safety, parking access, and electrical compliance.',
  'platform_only_facilitates_discovery_and_coordination':
      'I understand this platform only facilitates charger discovery and request coordination between users.',
};

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
      await _chargingService.decideChargerRequest(
        requestId: item.id,
        hostUserId: user.id,
        status: status,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'accepted' ? 'Request accepted.' : 'Request rejected.'),
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

  Future<void> _openSettlementSheet(ChargerRequestItem item) async {
    final user = ref.read(userProvider);
    if (user == null) return;

    final settled = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SessionSettlementSheet(
        item: item,
        hostUserId: user.id,
        chargingService: _chargingService,
      ),
    );

    if (settled == true) await _loadData();
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
              label: const Text('Share Charger'),
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
                            'Share your private EV charger',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Gap(8),
                          Text(
                            'Offer temporary EV charging access, keep payments manual by UPI or cash, and help travellers discover a trusted private charger near them.',
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
                        onSettle: item.status == 'accepted' && !item.isSettled
                            ? () => _openSettlementSheet(item)
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
  late final TextEditingController _electricityCostController;
  late final TextEditingController _hostMarginController;
  late final TextEditingController _pricePerSessionController;
  late final TextEditingController _availableFromController;
  late final TextEditingController _availableToController;
  late final TextEditingController _availableDaysController;
  late final TextEditingController _availableHoursController;
  late final TextEditingController _accessInstructionsController;
  late final TextEditingController _parkingNotesController;
  late final TextEditingController _houseRulesController;
  late String _selectedPropertyType;
  late String _selectedVisitorAccessType;
  late Map<String, bool> _locationAccessChecks;
  late Map<String, bool> _safetyChecks;
  late Map<String, bool> _hostDeclarations;
  late Map<String, bool> _vehicleSizeSupport;
  late List<String> _chargerPhotos;
  late List<String> _parkingPhotos;
  bool _isAcceptingRequests = true;
  bool _isSaving = false;
  bool _isUploadingChargerPhoto = false;
  bool _isUploadingParkingPhoto = false;

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
    _electricityCostController = TextEditingController(
      text: listing?.electricityCostPerKwh?.toString() ?? '',
    );
    _hostMarginController = TextEditingController(
      text: listing?.hostMarginPerKwh?.toString() ?? '',
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
    _availableHoursController = TextEditingController(
      text: listing?.availableHours ?? '',
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
    _selectedPropertyType = listing?.propertyType ?? _propertyTypeOptions.first;
    _selectedVisitorAccessType =
        listing?.visitorAccessType ?? _visitorAccessOptions.first;
    _locationAccessChecks = {
      for (final entry in _locationAccessLabels.entries)
        entry.key: listing?.locationAccessChecks[entry.key] ?? false,
    };
    _safetyChecks = {
      for (final entry in _safetyChecklistLabels.entries)
        entry.key: listing?.safetyChecks[entry.key] ?? false,
    };
    _hostDeclarations = {
      for (final entry in _hostDeclarationLabels.entries)
        entry.key: listing?.hostDeclarations[entry.key] ?? false,
    };
    _vehicleSizeSupport = {
      for (final size in _vehicleSizeOptions)
        size: listing?.vehicleSizeSupport.contains(size) ?? false,
    };
    _chargerPhotos = [...(listing?.chargerPhotos ?? const [])];
    _parkingPhotos = [...(listing?.parkingPhotos ?? const [])];
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
    _electricityCostController.dispose();
    _hostMarginController.dispose();
    _pricePerSessionController.dispose();
    _availableFromController.dispose();
    _availableToController.dispose();
    _availableDaysController.dispose();
    _availableHoursController.dispose();
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

  bool _allChecked(Map<String, bool> values) =>
      values.isNotEmpty && values.values.every((value) => value);

  Future<void> _pickAndUploadPhoto({required bool parkingPhoto}) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 86,
    );
    if (image == null || !mounted) return;

    setState(() {
      if (parkingPhoto) {
        _isUploadingParkingPhoto = true;
      } else {
        _isUploadingChargerPhoto = true;
      }
    });

    try {
      final url = await _service.uploadHostedChargerImage(image.path);
      if (url == null) {
        throw Exception('Upload failed');
      }

      if (!mounted) return;
      setState(() {
        if (parkingPhoto) {
          _parkingPhotos = [..._parkingPhotos, url];
        } else {
          _chargerPhotos = [..._chargerPhotos, url];
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not upload photo: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingParkingPhoto = false;
          _isUploadingChargerPhoto = false;
        });
      }
    }
  }

  void _removePhoto(String url, {required bool parkingPhoto}) {
    setState(() {
      if (parkingPhoto) {
        _parkingPhotos = _parkingPhotos.where((item) => item != url).toList();
      } else {
        _chargerPhotos = _chargerPhotos.where((item) => item != url).toList();
      }
    });
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
        electricityCostPerKwh: _parseDouble(_electricityCostController.text),
        hostMarginPerKwh: _parseDouble(_hostMarginController.text),
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
        availableHours: _availableHoursController.text.trim().isEmpty
            ? null
            : _availableHoursController.text.trim(),
        parkingNotes: _parkingNotesController.text.trim().isEmpty
            ? null
            : _parkingNotesController.text.trim(),
        houseRules: _houseRulesController.text.trim().isEmpty
            ? null
            : _houseRulesController.text.trim(),
        isAcceptingRequests: _isAcceptingRequests,
        chargerPhotos: _chargerPhotos,
        parkingPhotos: _parkingPhotos,
        propertyType: _selectedPropertyType,
        visitorAccessType: _selectedVisitorAccessType,
        vehicleSizeSupport: _vehicleSizeSupport.entries
            .where((entry) => entry.value)
            .map((entry) => entry.key)
            .toList(),
        locationAccessChecks: _locationAccessChecks,
        safetyChecks: _safetyChecks,
        hostDeclarations: _hostDeclarations,
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
                widget.existing == null
                    ? 'Share your private EV charger'
                    : 'Edit private EV charger',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'List a shared charger with simple access details, self-certified safety checks, and manual payment options. EVraahein helps hosts and drivers coordinate private charging access. It does not operate or guarantee a public charging network.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const Gap(16),
              _FormSectionCard(
                title: 'Basics',
                subtitle: 'Name, location, connector, access type, and hours',
                initiallyExpanded: true,
                isComplete:
                    _nameController.text.trim().isNotEmpty &&
                    _hostPhoneController.text.trim().isNotEmpty &&
                    _connectorTypesController.text.trim().isNotEmpty,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Listing name',
                        hintText: 'Home charger near Jubilee Hills',
                      ),
                      validator: (value) => value == null || value.trim().isEmpty
                          ? 'Required'
                          : null,
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
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
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
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _hostPhoneController,
                            decoration: const InputDecoration(
                              labelText: 'Host phone',
                            ),
                            keyboardType: TextInputType.phone,
                            validator: (value) => value == null || value.trim().isEmpty
                                ? 'Required'
                                : null,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: TextFormField(
                            controller: _hostUpiController,
                            decoration: const InputDecoration(
                              labelText: 'UPI ID (optional)',
                            ),
                          ),
                        ),
                      ],
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
                              labelText: 'Power (kW)',
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
                    DropdownButtonFormField<String>(
                      initialValue: _selectedPropertyType,
                      decoration: const InputDecoration(
                        labelText: 'Property type',
                      ),
                      items: _propertyTypeOptions
                          .map(
                            (option) => DropdownMenuItem(
                              value: option,
                              child: Text(option),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedPropertyType = value;
                        });
                      },
                    ),
                    if (_selectedPropertyType == 'Apartment/society parking') ...[
                      const Gap(8),
                      _InlineNotice(
                        text:
                            'Ensure your apartment/community permits visitor vehicle access before listing.',
                      ),
                    ],
                    const Gap(12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedVisitorAccessType,
                      decoration: const InputDecoration(
                        labelText: 'Visitor access type',
                      ),
                      items: _visitorAccessOptions
                          .map(
                            (option) => DropdownMenuItem(
                              value: option,
                              child: Text(option),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedVisitorAccessType = value;
                        });
                      },
                    ),
                    const Gap(12),
                    TextFormField(
                      controller: _availableHoursController,
                      decoration: const InputDecoration(
                        labelText: 'Available hours',
                        hintText: '24 hours, 6 AM – 10 PM, or On request only',
                      ),
                    ),
                    const Gap(12),
                    TextFormField(
                      controller: _availableDaysController,
                      decoration: const InputDecoration(
                        labelText: 'Available days (optional)',
                        hintText: 'Mon, Tue, Wed',
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              _FormSectionCard(
                title: 'Pricing',
                subtitle: 'Keep manual settlement simple and low-friction',
                initiallyExpanded: false,
                isComplete:
                    _pricePerSessionController.text.trim().isNotEmpty ||
                    _electricityCostController.text.trim().isNotEmpty,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hosts set a charging access/session amount. Suggested pricing may include electricity recovery cost, parking/access fee, and host convenience margin. Platform convenience fee may apply.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Gap(12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _electricityCostController,
                            decoration: const InputDecoration(
                              labelText: 'Electricity recovery cost',
                              prefixText: '₹ ',
                              suffixText: '/kWh',
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            validator: (value) =>
                                _validateOptionalNumber(value, allowZero: false),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: TextFormField(
                            controller: _hostMarginController,
                            decoration: const InputDecoration(
                              labelText: 'Host convenience margin',
                              prefixText: '₹ ',
                              suffixText: '/kWh',
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (_) => setState(() {}),
                            validator: (value) =>
                                _validateOptionalNumber(value, allowZero: true),
                          ),
                        ),
                      ],
                    ),
                    const Gap(8),
                    _PricingPreviewBanner(
                      electricityCost: _parseDouble(_electricityCostController.text),
                      hostMargin: _parseDouble(_hostMarginController.text),
                    ),
                    const Gap(12),
                    TextFormField(
                      controller: _pricePerSessionController,
                      decoration: const InputDecoration(
                        labelText: 'Charging access/session amount (optional)',
                        prefixText: '₹ ',
                      ),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (value) => _validateOptionalNumber(value),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              _FormSectionCard(
                title: 'Location & Access',
                subtitle: 'Traveller trust, approachability, and arrival notes',
                initiallyExpanded: false,
                isComplete: _allChecked(_locationAccessChecks),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in _locationAccessLabels.entries)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _locationAccessChecks[entry.key] ?? false,
                        onChanged: (value) {
                          setState(() {
                            _locationAccessChecks[entry.key] = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(entry.value),
                      ),
                    const Gap(8),
                    TextFormField(
                      controller: _accessInstructionsController,
                      decoration: const InputDecoration(
                        labelText: 'Arrival notes',
                        hintText:
                            'Gate, landmark, security note, or what drivers should know',
                      ),
                      maxLines: 3,
                    ),
                    const Gap(12),
                    TextFormField(
                      controller: _parkingNotesController,
                      decoration: const InputDecoration(
                        labelText: 'Parking/access notes',
                      ),
                      maxLines: 2,
                    ),
                    const Gap(12),
                    Text(
                      'Vehicle size support',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Gap(6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _vehicleSizeOptions.map((size) {
                        final selected = _vehicleSizeSupport[size] ?? false;
                        return FilterChip(
                          selected: selected,
                          label: Text(size),
                          onSelected: (value) {
                            setState(() {
                              _vehicleSizeSupport[size] = value;
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              _FormSectionCard(
                title: 'Safety Checklist',
                subtitle: 'Self-certify safe temporary charging conditions',
                initiallyExpanded: false,
                isComplete: _allChecked(_safetyChecks),
                child: Column(
                  children: [
                    for (final entry in _safetyChecklistLabels.entries)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _safetyChecks[entry.key] ?? false,
                        onChanged: (value) {
                          setState(() {
                            _safetyChecks[entry.key] = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(entry.value),
                      ),
                  ],
                ),
              ),
              const Gap(12),
              _FormSectionCard(
                title: 'Photos',
                subtitle: 'Optional, but strong trust builders for travellers',
                initiallyExpanded: false,
                isComplete:
                    _chargerPhotos.isNotEmpty && _parkingPhotos.isNotEmpty,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PhotoUploadRow(
                      title: 'Charger photo',
                      isUploading: _isUploadingChargerPhoto,
                      onUpload: () => _pickAndUploadPhoto(parkingPhoto: false),
                    ),
                    if (_chargerPhotos.isNotEmpty) ...[
                      const Gap(8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _chargerPhotos
                            .map(
                              (url) => _PhotoTag(
                                label: 'Charger photo',
                                onRemove: () =>
                                    _removePhoto(url, parkingPhoto: false),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                    const Gap(12),
                    _PhotoUploadRow(
                      title: 'Parking/access photo',
                      isUploading: _isUploadingParkingPhoto,
                      onUpload: () => _pickAndUploadPhoto(parkingPhoto: true),
                    ),
                    if (_parkingPhotos.isNotEmpty) ...[
                      const Gap(8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _parkingPhotos
                            .map(
                              (url) => _PhotoTag(
                                label: 'Parking photo',
                                onRemove: () =>
                                    _removePhoto(url, parkingPhoto: true),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(12),
              _FormSectionCard(
                title: 'Host Declaration',
                subtitle: 'Required to publish a private shared charger',
                initiallyExpanded: true,
                isComplete: _allChecked(_hostDeclarations),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in _hostDeclarationLabels.entries)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _hostDeclarations[entry.key] ?? false,
                        onChanged: (value) {
                          setState(() {
                            _hostDeclarations[entry.key] = value ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(entry.value),
                      ),
                    const Gap(8),
                    TextFormField(
                      controller: _houseRulesController,
                      decoration: const InputDecoration(
                        labelText: 'House rules (optional)',
                        hintText: 'Call before arrival, keep the gate closed, etc.',
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              const Gap(12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Accept charging requests'),
                subtitle: const Text(
                  'Keep this on only when you can respond and coordinate arrivals.',
                ),
                value: _isAcceptingRequests,
                onChanged: (value) {
                  setState(() {
                    _isAcceptingRequests = value;
                  });
                },
              ),
              const Gap(8),
              Text(
                'Traveller note shown on requests: "This is a privately hosted charger shared by an individual host. Verify connector compatibility, parking suitability, and availability before arrival."',
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
                      : const Text('Save private charger listing'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool initiallyExpanded;
  final bool isComplete;
  final Widget child;

  const _FormSectionCard({
    required this.title,
    required this.subtitle,
    required this.initiallyExpanded,
    required this.isComplete,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isComplete ? theme.colorScheme.primary : Colors.orange;

    return Card(
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isComplete ? 'Complete' : 'Needs review',
            style: theme.textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        children: [child],
      ),
    );
  }
}

class _InlineNotice extends StatelessWidget {
  final String text;

  const _InlineNotice({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _PhotoUploadRow extends StatelessWidget {
  final String title;
  final bool isUploading;
  final VoidCallback onUpload;

  const _PhotoUploadRow({
    required this.title,
    required this.isUploading,
    required this.onUpload,
  });

  @override
  Widget build(BuildContext context) {
    final uploadButton = OutlinedButton.icon(
      onPressed: isUploading ? null : onUpload,
      icon: isUploading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.upload_outlined),
      label: Text(isUploading ? 'Uploading' : 'Upload'),
    );

    return SizedBox(
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Gap(8),
                uploadButton,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Gap(12),
              uploadButton,
            ],
          );
        },
      ),
    );
  }
}

class _PhotoTag extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _PhotoTag({
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      onDeleted: onRemove,
    );
  }
}

class _MiniStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniStatusPill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
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
        'Suggested energy access ₹${listing.pricePerKwh!.toStringAsFixed(0)}/kWh',
      if (listing.electricityCostPerKwh != null && listing.hostMarginPerKwh != null)
        'Recovery ₹${listing.electricityCostPerKwh!.toStringAsFixed(0)} + '
        'margin ₹${listing.hostMarginPerKwh!.toStringAsFixed(0)}',
      if (listing.pricePerSession != null)
        '₹${listing.pricePerSession!.toStringAsFixed(0)} session amount',
      if ((listing.availableHours ?? '').isNotEmpty) listing.availableHours!,
      if (listing.availableDays.isNotEmpty) listing.availableDays.join(', '),
    ];
    final trustLabels = <String>[
      if (listing.verificationBadges['phone_verified'] == true) 'Phone verified',
      if (listing.verificationBadges['charger_photo_uploaded'] == true)
        'Charger photo uploaded',
      if (listing.verificationBadges['parking_photo_uploaded'] == true)
        'Parking photo uploaded',
      if (listing.verificationBadges['responsive_host'] == true) 'Responsive host',
      if (listing.verificationBadges['repeat_host'] == true) 'Repeat host',
    ];
    final safetyComplete =
        listing.safetyChecks.isNotEmpty &&
        listing.safetyChecks.values.every((value) => value);
    final accessComplete =
        listing.locationAccessChecks.isNotEmpty &&
        listing.locationAccessChecks.values.every((value) => value);

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
            if (trustLabels.isNotEmpty) ...[
              const Gap(8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: trustLabels
                    .map(
                      (label) => Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(label),
                      ),
                    )
                    .toList(),
              ),
            ],
            const Gap(8),
            Row(
              children: [
                _MiniStatusPill(
                  label: accessComplete ? 'Access reviewed' : 'Access needs review',
                  color: accessComplete ? theme.colorScheme.primary : Colors.orange,
                ),
                const Gap(8),
                _MiniStatusPill(
                  label: safetyComplete ? 'Safety reviewed' : 'Safety needs review',
                  color: safetyComplete ? theme.colorScheme.primary : Colors.orange,
                ),
              ],
            ),
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
  final VoidCallback? onSettle;

  const _RequestCard({
    required this.item,
    required this.showHostContact,
    this.onAccept,
    this.onReject,
    this.onSettle,
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
            // Estimated amount before settlement
            if (!item.isSettled && item.estimatedAmount != null) ...[
              const Gap(8),
              Text(
                'Estimated: ₹${item.estimatedAmount!.toStringAsFixed(0)} '
                '(incl. convenience fee if applicable)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            // Final bill after settlement
            if (item.isSettled) ...[
              const Gap(12),
              _FinalBillCard(item: item),
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
            if (onAccept != null || onReject != null || onSettle != null) ...[
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
                  if (onSettle != null)
                    FilledButton.tonal(
                      onPressed: onSettle,
                      child: const Text('Complete & Bill'),
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

/// Live preview shown in the host form as the host types electricity cost + margin.
class _PricingPreviewBanner extends StatelessWidget {
  final double? electricityCost;
  final double? hostMargin;

  static const double _platformFeePercent = 5.0;
  static const double _platformFeeMin = 2.0;

  const _PricingPreviewBanner({this.electricityCost, this.hostMargin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (electricityCost == null) {
      return const SizedBox.shrink();
    }

    final driverRatePerKwh = electricityCost! + (hostMargin ?? 0);
    // Example: 10 kWh session
    const exampleKwh = 10.0;
    final exampleEnergyCost = exampleKwh * driverRatePerKwh;
    final examplePlatformFee = (exampleEnergyCost * _platformFeePercent / 100)
        .clamp(_platformFeeMin, double.infinity);
    final exampleTotal = exampleEnergyCost + examplePlatformFee;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Suggested access pricing preview',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const Gap(6),
          _PreviewRow(
            'Suggested energy access amount',
            '₹${driverRatePerKwh.toStringAsFixed(2)}/kWh',
          ),
          _PreviewRow(
            'Possible platform convenience fee',
            '₹${(driverRatePerKwh * _platformFeePercent / 100).clamp(_platformFeeMin / exampleKwh, double.infinity).toStringAsFixed(2)}/kWh',
          ),
          const Divider(height: 12),
          _PreviewRow(
            'Example — $exampleKwh kWh charging access',
            '₹${exampleTotal.toStringAsFixed(0)}',
            bold: true,
          ),
          const Gap(4),
          Text(
            'This can help recover your electricity cost and host convenience margin on a typical ${exampleKwh.toInt()} kWh visit.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _PreviewRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Final bill breakdown shown on a settled request.
class _FinalBillCard extends StatelessWidget {
  final ChargerRequestItem item;

  const _FinalBillCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pricePerKwh = item.stationPricePerKwh;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 16, color: Colors.green),
              const Gap(6),
              Text(
                'Final Bill',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const Gap(8),
        if (item.kwhDelivered != null && pricePerKwh != null)
            _BillRow(
              '${item.kwhDelivered!.toStringAsFixed(2)} kWh × ₹${pricePerKwh.toStringAsFixed(2)}',
              '₹${item.energyCost!.toStringAsFixed(2)}',
            ),
          if (item.platformFee != null)
            _BillRow('Convenience fee', '₹${item.platformFee!.toStringAsFixed(2)}'),
          const Divider(height: 12),
          _BillRow(
            'Total',
            '₹${item.finalAmount!.toStringAsFixed(2)}',
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _BillRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
        : Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Bottom sheet where the host enters actual kWh delivered to complete + settle.
class _SessionSettlementSheet extends StatefulWidget {
  final ChargerRequestItem item;
  final String hostUserId;
  final ChargingService chargingService;

  const _SessionSettlementSheet({
    required this.item,
    required this.hostUserId,
    required this.chargingService,
  });

  @override
  State<_SessionSettlementSheet> createState() => _SessionSettlementSheetState();
}

class _SessionSettlementSheetState extends State<_SessionSettlementSheet> {
  final _kwhController = TextEditingController();
  bool _isSaving = false;

  static const double _platformFeePercent = 5.0;
  static const double _platformFeeMin = 2.0;

  double? get _kwh => double.tryParse(_kwhController.text.trim());
  double? get _pricePerKwh => widget.item.stationPricePerKwh;

  double? get _energyCost {
    final kwh = _kwh;
    final rate = _pricePerKwh;
    if (kwh == null || rate == null || kwh <= 0) return null;
    return kwh * rate;
  }

  double? get _platformFee {
    final energy = _energyCost;
    if (energy == null) return null;
    return (energy * _platformFeePercent / 100).clamp(_platformFeeMin, double.infinity);
  }

  double? get _total {
    final energy = _energyCost;
    final fee = _platformFee;
    if (energy == null || fee == null) return null;
    return energy + fee;
  }

  Future<void> _settle() async {
    final kwh = _kwh;
    if (kwh == null || kwh <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid kWh amount.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await widget.chargingService.settleChargerRequest(
        requestId: widget.item.id,
        hostUserId: widget.hostUserId,
        kwhDelivered: kwh,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Settlement failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _kwhController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final stationName = widget.item.station?['name']?.toString() ?? 'Hosted Charger';

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.bolt_outlined),
                const Gap(8),
                Expanded(
                  child: Text(
                    'Complete & Bill — $stationName',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Gap(4),
            if ((widget.item.requesterName ?? '').isNotEmpty)
              Text(
                'Driver: ${widget.item.requesterName}  •  ${widget.item.vehicleName ?? ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const Gap(16),
            TextFormField(
              controller: _kwhController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Actual kWh delivered',
                suffixText: 'kWh',
                hintText: 'e.g. 8.5',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const Gap(16),
            if (_pricePerKwh != null && _kwh != null && _kwh! > 0) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _BillRow(
                      '${_kwhController.text.trim()} kWh × ₹${_pricePerKwh!.toStringAsFixed(2)}/kWh',
                      '₹${_energyCost!.toStringAsFixed(2)}',
                    ),
                    _BillRow(
                      'Platform fee (5%, min ₹$_platformFeeMin)',
                      '₹${_platformFee!.toStringAsFixed(2)}',
                    ),
                    const Divider(height: 16),
                    _BillRow(
                      'Driver pays total',
                      '₹${_total!.toStringAsFixed(2)}',
                      bold: true,
                    ),
                    const Gap(4),
                    _BillRow(
                      'You earn (excl. electricity cost)',
                      '₹${((_kwh! * (widget.item.stationPricePerKwh ?? 0)) - (_kwh! * (widget.item.station?['electricity_cost_per_kwh'] as num? ?? 0).toDouble())).toStringAsFixed(2)}',
                    ),
                  ],
                ),
              ),
              const Gap(16),
            ],
            if (_pricePerKwh == null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'No per-kWh price is set for this charger. '
                  'Edit your listing to add a price before settling.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              const Gap(16),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_isSaving || _total == null) ? null : _settle,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _total != null
                      ? 'Confirm — ₹${_total!.toStringAsFixed(0)} due'
                      : 'Enter kWh to continue',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
