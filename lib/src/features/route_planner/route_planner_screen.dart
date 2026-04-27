import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'here_routing_service.dart';
import 'route_model.dart';
import '../mapping/places_service.dart';
import '../vehicle_profile/vehicle_provider.dart';
import '../vehicle_profile/vehicle_model.dart';
import 'saved_routes_screen.dart';

class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> with SingleTickerProviderStateMixin {
  final _startController = TextEditingController();
  final _destController = TextEditingController();
  final _hereService = HereRoutingService();
  
  bool _isLoading = false;
  int _currentSoc = 80;
  int _targetSoc = 20;
  int _soh = 100;
  bool _isRoundTrip = false;
  int _shortStayDuration = 60;
  String _tripStyle = 'balanced';

  String? _startPlaceId;
  String? _destPlaceId;
  String? _selectedVehicleId;
  final _placesService = PlacesService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _planTrip() async {
    if (_startPlaceId == null || _destPlaceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and destination from suggestions')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final vehicles = ProviderScope.containerOf(context).read(vehicleProvider);

      // 1. Get Coordinates
      final startLatLng = await _placesService.getPlaceDetails(_startPlaceId!);
      final destLatLng = await _placesService.getPlaceDetails(_destPlaceId!);

      if (startLatLng == null || destLatLng == null) {
        throw Exception('Failed to get coordinates for selected locations');
      }

      VehicleProfile? selectedVehicle;
      if (_selectedVehicleId != null) {
        for (final vehicle in vehicles) {
          if (vehicle.id == _selectedVehicleId) {
            selectedVehicle = vehicle;
            break;
          }
        }
      }

      // 2. Calculate Route
      final routes = await _hereService.calculateEVRoutes(
        origin: startLatLng,
        destination: destLatLng,
        currentSoc: _currentSoc,
        targetSoc: _targetSoc,
        soh: _soh,
        vehicle: selectedVehicle,
        isRoundTrip: _isRoundTrip,
        shortStayDurationMin: _isRoundTrip ? _shortStayDuration : 0,
      );

      if (routes.isEmpty) {
        throw Exception(
          'No route options were returned. Please try different charge settings or locations.',
        );
      }

      if (mounted) {
        context.push('/planner/result', extra: {
          'routes': routes,
          'vehicleId': _selectedVehicleId,
          'startAddress': _startController.text,
          'endAddress': _destController.text,
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error planning trip: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  bool _showOptions = false;

  void _applyTripStyle(String style) {
    setState(() {
      _tripStyle = style;
      switch (style) {
        case 'fastest':
          _targetSoc = 12;
          _shortStayDuration = 30;
          break;
        case 'comfort':
          _targetSoc = 28;
          _shortStayDuration = 90;
          break;
        default:
          _targetSoc = 20;
          _shortStayDuration = 60;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Plan Your Trip'),
        backgroundColor: theme.colorScheme.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: TabBar(
            controller: _tabController,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: const [
              Tab(text: 'Plan Trip', height: 32),
              Tab(text: 'Saved Plans', height: 32),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Plan Trip Form
          _buildPlanTripForm(theme),
          // Tab 2: Saved Plans
          const SavedRoutesList(),
        ],
      ),
    );
  }

  Widget _buildPlanTripForm(ThemeData theme) {
    return Stack(
        children: [
          // No Background Map

          // Floating Input Card
          SafeArea(
            child: Column(
              children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 2,
                          shadowColor: Colors.black26,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Inputs
                                Row(
                                  children: [
                                    Column(
                                      children: [
                                        Icon(
                                          PhosphorIcons.circle(
                                            PhosphorIconsStyle.fill,
                                          ),
                                          size: 12,
                                          color: theme.colorScheme.primary,
                                        ),
                                  Container(width: 2, height: 24, color: theme.colorScheme.outlineVariant),
                                  Icon(
                                    PhosphorIcons.mapPin(
                                      PhosphorIconsStyle.fill,
                                    ),
                                    size: 16,
                                    color: theme.colorScheme.error,
                                  ),
                                      ],
                                    ),
                                    const Gap(12),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          _LocationAutocomplete(
                                            controller: _startController,
                                            label: 'Start Location',
                                            onSelected: (selection) {
                                              setState(() {
                                                _startPlaceId = selection['place_id'];
                                              });
                                            },
                                          ),
                                          Divider(height: 1, color: theme.colorScheme.outlineVariant),
                                          _LocationAutocomplete(
                                            controller: _destController,
                                            label: 'Destination',
                                            onSelected: (selection) {
                                              setState(() {
                                                _destPlaceId = selection['place_id'];
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Gap(12),
                                _buildVehicleSelector(theme),
                                const Gap(10),
                                Container(
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.surfaceContainerLowest,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                  ),
                                  child: ExpansionTile(
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(16)),
                                    ),
                                    collapsedShape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.all(Radius.circular(16)),
                                    ),
                                    initiallyExpanded: _showOptions,
                                    onExpansionChanged: (value) {
                                      setState(() {
                                        _showOptions = value;
                                      });
                                    },
                                    tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    childrenPadding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      16,
                                    ),
                                    title: Text(
                                      'Advanced trip settings',
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Trip style, battery buffers, and round-trip controls',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    children: [
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Trip style',
                                          style: theme.textTheme.labelLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const Gap(8),
                                      SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            _TripStyleChip(
                                              label: 'Fastest',
                                              description: 'Lower reserve, faster arrival',
                                              isSelected: _tripStyle == 'fastest',
                                              onTap: () => _applyTripStyle('fastest'),
                                            ),
                                            const Gap(8),
                                            _TripStyleChip(
                                              label: 'Balanced',
                                              description: 'Default comfort buffer',
                                              isSelected: _tripStyle == 'balanced',
                                              onTap: () => _applyTripStyle('balanced'),
                                            ),
                                            const Gap(8),
                                            _TripStyleChip(
                                              label: 'Battery Safe',
                                              description: 'More reserve at stops',
                                              isSelected: _tripStyle == 'comfort',
                                              onTap: () => _applyTripStyle('comfort'),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Gap(10),
                                      _buildSliderRow(
                                        context,
                                        'Current SOC',
                                        '$_currentSoc%',
                                        _currentSoc.toDouble(),
                                        0,
                                        100,
                                        (v) => setState(() => _currentSoc = v.round()),
                                        info: 'State of Charge: The current battery percentage of your vehicle.',
                                      ),
                                      _buildSliderRow(
                                        context,
                                        'Target SOC',
                                        '$_targetSoc%',
                                        _targetSoc.toDouble(),
                                        0,
                                        100,
                                        (v) => setState(() => _targetSoc = v.round()),
                                        info: 'Target SOC: The minimum battery percentage you want to have when you reach your destination.',
                                      ),
                                      _buildSliderRow(
                                        context,
                                        'Battery SOH',
                                        '$_soh%',
                                        _soh.toDouble(),
                                        50,
                                        100,
                                        (v) => setState(() => _soh = v.round()),
                                        info: 'State of Health: The current health of your battery relative to when it was new. Lower SOH reduces range.',
                                      ),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Round Trip', style: theme.textTheme.bodyMedium),
                                          Switch(
                                            value: _isRoundTrip,
                                            onChanged: (v) => setState(() => _isRoundTrip = v),
                                          ),
                                        ],
                                      ),
                                      if (_isRoundTrip)
                                        _buildSliderRow(
                                          context,
                                          'Stay Duration',
                                          '${_shortStayDuration}m',
                                          _shortStayDuration.toDouble(),
                                          0,
                                          240,
                                          (v) => setState(() => _shortStayDuration = v.round()),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  // Floating Action Button for Planning
                  
                  // Floating Action Button for Planning
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _planTrip,
                        style: FilledButton.styleFrom(
                          elevation: 2,
                          shadowColor: Colors.black45,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: _isLoading 
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.directions, size: 18),
                        label: const Text('Plan Route', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
  }

  Widget _buildSliderRow(BuildContext context, String label, String valueLabel, double value, double min, double max, ValueChanged<double> onChanged, {String? info}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                if (info != null)
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(label),
                          content: Text(info),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                          ],
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
              ],
            ),
            Text(valueLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildVehicleSelector(ThemeData theme) {
    return Consumer(
      builder: (context, ref, child) {
        final vehicles = ref.watch(vehicleProvider);
        final vehicleNotifier = ref.read(vehicleProvider.notifier);

        if (vehicles.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.directions_car_outlined,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                    const Gap(10),
                    Text(
                      'Vehicle',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Gap(8),
                Text(
                  'Add your EV once to get route plans based on your battery and real-world range.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Gap(12),
                FilledButton.icon(
                  onPressed: () => context.push('/setup/vehicle/add'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Vehicle'),
                ),
              ],
            ),
          );
        }

        if (_selectedVehicleId == null && vehicles.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                final primary = vehicleNotifier.primaryVehicle;
                _selectedVehicleId = primary?.id ?? vehicles.first.id;
              });
            }
          });
        }

        final selectedVehicle = vehicles.where((v) => v.id == _selectedVehicleId).toList();
        final currentVehicle = selectedVehicle.isNotEmpty ? selectedVehicle.first : null;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Vehicle',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedVehicleId,
                    hint: const Text('Select Vehicle'),
                    items: vehicles.map((v) {
                      return DropdownMenuItem(
                        value: v.id,
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: theme.colorScheme.surfaceContainerHighest,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: (v.photoUrl != null || v.imageUrl != null)
                                  ? Image.network(
                                      v.photoUrl ?? v.imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => Icon(
                                        Icons.directions_car,
                                        size: 16,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : Icon(
                                      Icons.directions_car,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '${v.brand} ${v.model}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (v.isPrimary) ...[
                                        const Gap(4),
                                        Icon(
                                          Icons.star,
                                          size: 12,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    '${v.variant} • ${v.estimatedRange.toInt()} km',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (id) {
                      setState(() {
                        _selectedVehicleId = id;
                      });
                    },
                  ),
                ),
              ),
              if (currentVehicle != null) ...[
                const Gap(10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildVehicleChip(
                        context,
                        icon: Icons.speed,
                        value: '${(currentVehicle.rangeEfficiency * 100).toInt()}%',
                        label: 'Efficiency',
                      ),
                      const Gap(6),
                      _buildVehicleChip(
                        context,
                        icon: Icons.battery_charging_full,
                        value: '${currentVehicle.estimatedRange.toInt()} km',
                        label: 'Range',
                      ),
                      if (currentVehicle.preferredChargingNetworks.isNotEmpty) ...[
                        const Gap(6),
                        _buildVehicleChip(
                          context,
                          icon: Icons.ev_station,
                          value: '${currentVehicle.preferredChargingNetworks.length}',
                          label: 'Networks',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildVehicleChip(BuildContext context, {required IconData icon, required String label, required String value}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const Gap(4),
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Gap(4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

String _routeHighlightTag(RouteModel route) {
  final chargingStops =
      route.stops.where((stop) => stop.type == StopType.charging).length;
  if (chargingStops == 0) {
    return 'Non-stop';
  }
  if (route.estimatedCost <= 350) {
    return 'Lowest Cost';
  }
  if (route.totalDurationMin <= 240) {
    return 'Quickest';
  }
  return 'Balanced';
}

class TripSummarySheet extends StatelessWidget {
  final RouteModel route;
  final VoidCallback? onSave;
  final bool isSaving;

  const TripSummarySheet({
    super.key, 
    required this.route,
    this.onSave,
    this.isSaving = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.14,
      minChildSize: 0.09,
      maxChildSize: 0.42,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 30,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Gap(8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      route.name,
                      style: theme.textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Gap(8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _routeHighlightTag(route),
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
              const Gap(6),
              _buildInfoRow(context, 'Total Distance', '${route.totalDistanceKm.toStringAsFixed(1)} km'),
              _buildInfoRow(context, 'Est. Time', '${(route.totalDurationMin / 60).toStringAsFixed(1)} hrs'),
              _buildInfoRow(context, 'Est. Cost', '₹${route.estimatedCost.toStringAsFixed(0)}'),
              const Divider(height: 18),
              if (route.guidance.isNotEmpty) ...[
                Text('Trip Guidance', style: theme.textTheme.titleSmall),
                const Gap(8),
                ...route.guidance.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(Icons.check_circle_outline, size: 16),
                        ),
                        const Gap(8),
                        Expanded(
                          child: Text(
                            item,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 18),
              ],
              Text('Charging Stops', style: theme.textTheme.titleSmall),
              const Gap(8),
              ...route.stops
                  .where((s) => s.type == StopType.charging)
                  .toList()
                  .asMap()
                  .entries
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildChargingStopCard(
                        context,
                        stop: entry.value,
                        stepIndex: entry.key + 1,
                      ),
                    ),
                  ),
              if (route.stops.where((s) => s.type == StopType.charging).isEmpty)
                Text(
                  'No charging stops needed for this trip!',
                  style: theme.textTheme.bodySmall,
                ),
                
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: isSaving ? null : onSave,
                      icon: isSaving 
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) 
                          : const Icon(Icons.save_alt, size: 18),
                      label: Text(isSaving ? 'Saving...' : 'Save'),
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () async {
                        // Safety check: ensure route has stops
                        if (route.stops.isEmpty) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No route stops available for navigation')),
                            );
                          }
                          return;
                        }
                        
                        // Launch navigation in maps app
                        try {
                          final origin = route.stops.first.location;
                          final destination = route.stops.last.location;
                          
                          final availableMaps = await MapLauncher.installedMaps;
                          
                          if (availableMaps.isEmpty) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('No map apps installed')),
                              );
                            }
                            return;
                          }
                          
                          // Use first available map (usually Google Maps on Android, Apple Maps on iOS)
                          await availableMaps.first.showDirections(
                            destination: Coords(destination.latitude, destination.longitude),
                            origin: Coords(origin.latitude, origin.longitude),
                            directionsMode: DirectionsMode.driving,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error launching navigation: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.navigation, size: 18),
                      label: const Text('Navigate'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey)),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildChargingStopCard(
    BuildContext context, {
    required RouteStop stop,
    required int stepIndex,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _showChargingStopActions(context, stop),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '$stepIndex',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (stop.advice != null && stop.advice!.isNotEmpty)
                        Text(
                          stop.advice!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            const Gap(12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (stop.chargeDurationMin != null)
                  _buildStopMetaChip(
                    context,
                    icon: Icons.bolt,
                    text: '${stop.chargeDurationMin} min charge',
                  ),
                if (stop.targetSoc != null)
                  _buildStopMetaChip(
                    context,
                    icon: Icons.battery_charging_full,
                    text: 'Target ${stop.targetSoc}%',
                  ),
                if (stop.arrivalSoc != null && stop.departureSoc != null)
                  _buildStopMetaChip(
                    context,
                    icon: Icons.swap_horiz,
                    text: '${stop.arrivalSoc}% -> ${stop.departureSoc}%',
                  ),
                if (stop.cost != null)
                  _buildStopMetaChip(
                    context,
                    icon: Icons.currency_rupee,
                    text: '₹${stop.cost!.toStringAsFixed(0)} est.',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showChargingStopActions(BuildContext context, RouteStop stop) async {
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stop.name, style: theme.textTheme.titleMedium),
                const Gap(6),
                if (stop.advice != null && stop.advice!.isNotEmpty)
                  Text(
                    stop.advice!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const Gap(10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (stop.chargeDurationMin != null)
                      _buildStopMetaChip(
                        context,
                        icon: Icons.bolt,
                        text: '${stop.chargeDurationMin} min',
                      ),
                    if (stop.targetSoc != null)
                      _buildStopMetaChip(
                        context,
                        icon: Icons.battery_charging_full,
                        text: 'To ${stop.targetSoc}%',
                      ),
                    if (stop.arrivalSoc != null)
                      _buildStopMetaChip(
                        context,
                        icon: Icons.battery_3_bar,
                        text: 'Arrive ${stop.arrivalSoc}%',
                      ),
                    if (stop.departureSoc != null)
                      _buildStopMetaChip(
                        context,
                        icon: Icons.battery_full,
                        text: 'Leave ${stop.departureSoc}%',
                      ),
                  ],
                ),
                const Gap(14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      await _openChargingStopInMaps(context, stop);
                    },
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('Open in Maps'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStopMetaChip(BuildContext context, {required IconData icon, required String text}) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const Gap(4),
          Text(text, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }

  Future<void> _openChargingStopInMaps(BuildContext context, RouteStop stop) async {
    try {
      final availableMaps = await MapLauncher.installedMaps;
      if (availableMaps.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No map apps installed')),
          );
        }
        return;
      }

      await availableMaps.first.showMarker(
        coords: Coords(stop.location.latitude, stop.location.longitude),
        title: stop.name,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open charging stop: $e')),
        );
      }
    }
  }
}

class _TripStyleChip extends StatelessWidget {
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _TripStyleChip({
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Gap(4),
            Text(
              description,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final Function(Map<String, String>) onSelected;

  const _LocationAutocomplete({
    required this.controller,
    required this.label,
    required this.onSelected,
  });

  @override
  State<_LocationAutocomplete> createState() => _LocationAutocompleteState();
}

class _LocationAutocompleteState extends State<_LocationAutocomplete> {
  final _placesService = PlacesService();
  
  @override
  Widget build(BuildContext context) {
    return Autocomplete<Map<String, String>>(
      optionsBuilder: (TextEditingValue textEditingValue) async {
        if (textEditingValue.text.length < 3) {
          return const Iterable<Map<String, String>>.empty();
        }
        return await _placesService.getAutocompleteSuggestions(textEditingValue.text);
      },
      displayStringForOption: (Map<String, String> option) => option['description'] ?? '',
      onSelected: (Map<String, String> selection) {
        widget.controller.text = selection['description']!;
        widget.onSelected(selection);
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        if (textEditingController.text != widget.controller.text) {
           textEditingController.text = widget.controller.text;
        }
        
        textEditingController.addListener(() {
          widget.controller.text = textEditingController.text;
        });

        return TextField(
          controller: textEditingController,
          focusNode: focusNode,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            labelText: widget.label,
            labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 4),
            isDense: true,
            suffixIcon: textEditingController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  onPressed: () {
                    textEditingController.clear();
                    widget.controller.clear();
                  },
                )
              : null,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: MediaQuery.of(context).size.width - 80,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    title: Text(option['description'] ?? ''),
                    onTap: () => onSelected(option),
                    leading: const Icon(Icons.location_on, size: 16, color: Colors.grey),
                    dense: true,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
