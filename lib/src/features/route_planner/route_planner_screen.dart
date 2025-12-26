import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:map_launcher/map_launcher.dart';
import 'here_routing_service.dart';
import 'route_model.dart';
import '../mapping/places_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../vehicle_profile/vehicle_provider.dart';
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
      // 1. Get Coordinates
      final startLatLng = await _placesService.getPlaceDetails(_startPlaceId!);
      final destLatLng = await _placesService.getPlaceDetails(_destPlaceId!);

      if (startLatLng == null || destLatLng == null) {
        throw Exception('Failed to get coordinates for selected locations');
      }

      // 2. Calculate Route
      final routes = await _hereService.calculateEVRoutes(
        origin: startLatLng,
        destination: destLatLng,
        currentSoc: _currentSoc,
        targetSoc: _targetSoc,
        soh: _soh,
        isRoundTrip: _isRoundTrip,
        shortStayDurationMin: _isRoundTrip ? _shortStayDuration : 0,
      );

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

  bool _showOptions = true; // Default to true to show new options

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Plan Your Trip'),
        backgroundColor: theme.colorScheme.surface,
        toolbarHeight: 48,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: TabBar(
            controller: _tabController,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            tabs: const [
              Tab(text: 'Plan Trip', height: 36),
              Tab(text: 'Saved Plans', height: 36),
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
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 4,
                          shadowColor: Colors.black26,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Inputs
                                Row(
                                  children: [
                                    Column(
                                      children: [
                                        Icon(PhosphorIcons.circle(PhosphorIconsStyle.fill), size: 12, color: Colors.blue),
                                  Container(width: 2, height: 24, color: theme.colorScheme.outlineVariant),
                                  Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.fill), size: 16, color: Colors.red),
                                      ],
                                    ),
                                    const Gap(16),
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
                                
                                // Options
                                if (_showOptions) ...[
                                  const Gap(4),
                                  // Vehicle Selection Dropdown
                                  Consumer(
                                    builder: (context, ref, child) {
                                      final vehicles = ref.watch(vehicleProvider);
                                      final vehicleNotifier = ref.read(vehicleProvider.notifier);
                                      
                                      // Initialize selected vehicle with primary vehicle if not set
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
                                      
                                      // Get selected vehicle for specs display
                                      final selectedVehicle = vehicles.where((v) => v.id == _selectedVehicleId).toList();
                                      final currentVehicle = selectedVehicle.isNotEmpty ? selectedVehicle.first : null;
                                      
                                      return Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                            decoration: BoxDecoration(
                                              border: Border.all(color: theme.colorScheme.outlineVariant),
                                              borderRadius: BorderRadius.circular(8),
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
                                                        // Vehicle image/icon
                                                        Container(
                                                          width: 32,
                                                          height: 32,
                                                          margin: const EdgeInsets.only(right: 10),
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
                                                                    size: 18,
                                                                    color: theme.colorScheme.primary,
                                                                  ),
                                                                )
                                                              : Icon(
                                                                  Icons.directions_car,
                                                                  size: 18,
                                                                  color: theme.colorScheme.primary,
                                                                ),
                                                        ),
                                                        // Vehicle details
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
                                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                                        fontWeight: FontWeight.w600,
                                                                      ),
                                                                      overflow: TextOverflow.ellipsis,
                                                                    ),
                                                                  ),
                                                                  if (v.isPrimary) ...[
                                                                    const Gap(4),
                                                                    Icon(
                                                                      Icons.star,
                                                                      size: 14,
                                                                      color: theme.colorScheme.primary,
                                                                    ),
                                                                  ],
                                                                ],
                                                              ),
                                                              Text(
                                                                '${v.variant} • ${v.estimatedRange.toInt()} km',
                                                                style: theme.textTheme.bodySmall?.copyWith(
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
                                          // Vehicle Specs Card
                                          if (currentVehicle != null) ...[
                                            const Gap(8),
                                            Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: _buildSpecItem(
                                                      context,
                                                      icon: Icons.speed,
                                                      label: 'Efficiency',
                                                      value: '${(currentVehicle.rangeEfficiency * 100).toInt()}%',
                                                    ),
                                                  ),
                                                  Container(
                                                    width: 1,
                                                    height: 30,
                                                    color: theme.colorScheme.outlineVariant,
                                                  ),
                                                  Expanded(
                                                    child: _buildSpecItem(
                                                      context,
                                                      icon: Icons.battery_charging_full,
                                                      label: 'Range',
                                                      value: '${currentVehicle.estimatedRange.toInt()} km',
                                                    ),
                                                  ),
                                                  if (currentVehicle.preferredChargingNetworks.isNotEmpty) ...[
                                                    Container(
                                                      width: 1,
                                                      height: 30,
                                                      color: theme.colorScheme.outlineVariant,
                                                    ),
                                                    Expanded(
                                                      child: _buildSpecItem(
                                                        context,
                                                        icon: Icons.ev_station,
                                                        label: 'Networks',
                                                        value: '${currentVehicle.preferredChargingNetworks.length}',
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      );
                                    },
                                  ),
                                  const Gap(8),
                                  const Divider(height: 1),
                                  const Gap(4),
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
                                    _buildSliderRow(context, 'Stay Duration', '${_shortStayDuration}m', _shortStayDuration.toDouble(), 0, 240, (v) => setState(() => _shortStayDuration = v.round())),
                                ],
                                
                                const Gap(8),
                                GestureDetector(
                                  onTap: () => setState(() => _showOptions = !_showOptions),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _showOptions ? 'Hide Options' : 'More Options',
                                        style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                                      ),
                                      Icon(
                                        _showOptions ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                        color: theme.colorScheme.primary,
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _planTrip,
                        style: FilledButton.styleFrom(
                          elevation: 4,
                          shadowColor: Colors.black45,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        ),
                        icon: _isLoading 
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.directions),
                        label: const Text('Plan Route', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

  Widget _buildSpecItem(BuildContext context, {required IconData icon, required String label, required String value}) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const Gap(2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
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
      initialChildSize: 0.4,
      minChildSize: 0.2,
      maxChildSize: 0.6,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, spreadRadius: 2),
            ],
          ),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Gap(24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(route.name, style: theme.textTheme.headlineSmall),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Best Value', // Logic to determine tag
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                    ),
                  ),
                ],
              ),
              const Gap(16),
              _buildInfoRow(context, 'Total Distance', '${route.totalDistanceKm.toStringAsFixed(1)} km'),
              _buildInfoRow(context, 'Est. Time', '${(route.totalDurationMin / 60).toStringAsFixed(1)} hrs'),
              _buildInfoRow(context, 'Est. Cost', '₹${route.estimatedCost.toStringAsFixed(0)}'),
              const Divider(height: 32),
              Text('Charging Stops', style: theme.textTheme.titleMedium),
              const Gap(16),
              ...route.stops.where((s) => s.type == StopType.charging).map((stop) => ListTile(
                leading: const Icon(Icons.ev_station, color: Colors.green),
                title: Text(stop.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Charge: ${stop.chargeDurationMin} mins • Target ${stop.targetSoc}% SOC'),
                    if (stop.arrivalSoc != null && stop.departureSoc != null)
                      Text('SOC: ${stop.arrivalSoc}% → ${stop.departureSoc}%', style: theme.textTheme.bodySmall),
                    if (stop.cost != null)
                      Text('Est. Cost: ₹${stop.cost!.toStringAsFixed(0)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                contentPadding: EdgeInsets.zero,
                isThreeLine: true,
              )),
              if (route.stops.where((s) => s.type == StopType.charging).isEmpty)
                const Text('No charging stops needed for this trip!'),
                
              const Gap(24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isSaving ? null : onSave,
                      icon: isSaving 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                          : const Icon(Icons.save_alt),
                      label: Text(isSaving ? 'Saving...' : 'Save Plan'),
                    ),
                  ),
                  const Gap(16),
                  Expanded(
                    child: FilledButton.icon(
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
                      icon: const Icon(Icons.navigation),
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
