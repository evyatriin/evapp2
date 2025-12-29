import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../community/check_in_sheet.dart';
import '../charge/cost_calculator_sheet.dart';
import 'stations_repository.dart';
import 'station_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'saved_chargers_list.dart';
import '../community/gamification_widgets.dart';
import '../authentication/user_provider.dart';
import '../../common_widgets/location_autocomplete.dart';
import 'places_service.dart';
import '../charge/charging_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng? _currentCameraPosition;
  double _currentZoom = 12.0;
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String? _selectedPlaceId;
  final _placesService = PlacesService();

  Future<void> _searchLocation(String placeId) async {
    if (placeId.isEmpty) return;
    try {
      final location = await _placesService.getPlaceDetails(placeId);
      if (location != null) {
        final target = LatLng(location.latitude, location.longitude);
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(target, 14));
        
        // Update provider to fetch chargers
        ref.read(mapCenterProvider.notifier).update(
          ll.LatLng(location.latitude, location.longitude),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location not found')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error finding location: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationsAsync = ref.watch(stationsProvider);
    final stations = stationsAsync.asData?.value ?? [];
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            indicatorWeight: 2,
            tabs: const [
              Tab(text: 'Find Chargers', height: 36),
              Tab(text: 'Saved Chargers', height: 36),
            ],
          ),
        ),
        // Connector Filter Chips
        Container(
          color: theme.colorScheme.surface,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Consumer(
              builder: (context, ref, child) {
                final selectedFilters = ref.watch(connectorFilterProvider);
                const connectors = ['CCS2', 'Type 2', 'CHAdeMO', 'GB/T'];
                return Row(
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: selectedFilters.isEmpty,
                      onSelected: (_) => ref.read(connectorFilterProvider.notifier).clear(),
                    ),
                    const SizedBox(width: 8),
                    ...connectors.map((connector) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(connector),
                        selected: selectedFilters.contains(connector),
                        onSelected: (_) => ref.read(connectorFilterProvider.notifier).toggle(connector),
                      ),
                    )),
                  ],
                );
              },
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Map with Search
              Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: const CameraPosition(
                      target: LatLng(17.3850, 78.4867), // Hyderabad
                      zoom: 12.0,
                    ),
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                    markers: stations.map((station) {
                      return Marker(
                        markerId: MarkerId(station.id),
                        position: LatLng(station.location.latitude, station.location.longitude),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (context) => DraggableScrollableSheet(
                              initialChildSize: 0.5,
                              minChildSize: 0.3,
                              maxChildSize: 0.9,
                              expand: false,
                              builder: (context, scrollController) => SingleChildScrollView(
                                controller: scrollController,
                                child: _StationDetailsSheet(station: station),
                              ),
                            ),
                          );
                        },
                        icon: BitmapDescriptor.defaultMarkerWithHue(
                          station.isPrivate
                              ? BitmapDescriptor.hueViolet // Private
                              : station.status == 'working'
                                  ? BitmapDescriptor.hueGreen
                                  : station.status == 'busy'
                                      ? BitmapDescriptor.hueOrange
                                      : BitmapDescriptor.hueRed,
                        ),
                      );
                    }).toSet(),
                    onMapCreated: (controller) {
                      _mapController = controller;
                    },
                    onCameraMove: (position) {
                      _currentCameraPosition = position.target;
                      _currentZoom = position.zoom;
                    },
                    onCameraIdle: () {
                      if (_currentCameraPosition != null) {
                        ref.read(mapCenterProvider.notifier).update(
                          ll.LatLng(_currentCameraPosition!.latitude, _currentCameraPosition!.longitude),
                        );
                        ref.read(mapZoomProvider.notifier).update(_currentZoom);
                      }
                    },
                  ),
                  
                  // Streak Widget Overlay
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Consumer(
                      builder: (context, ref, child) {
                        final user = ref.watch(userProvider);
                        if (user == null || user.streak == 0) return const SizedBox.shrink();
                        return StreakWidget(streak: user.streak);
                      },
                    ),
                  ),
                  
                  // Search Bar
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      elevation: 4,
                      child: LocationAutocomplete(
                        controller: _searchController,
                        hintText: 'Search location...',
                        onSelected: (selection) {
                          _selectedPlaceId = selection['place_id'];
                          if (_selectedPlaceId != null) {
                            _searchLocation(_selectedPlaceId!);
                          }
                        },
                      ),
                    ),
                  ),

                  // Loading Indicator Overlay
                  if (stationsAsync.isLoading)
                    Positioned(
                      top: 80,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 8),
                                Text('Searching area...'),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    
                  // Error Overlay
                  if (stationsAsync.hasError)
                     Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: Card(
                        color: theme.colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Text(
                            'Error loading stations: ${stationsAsync.error}',
                            style: TextStyle(color: theme.colorScheme.onErrorContainer),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              // Tab 2: Saved Chargers
              const SavedChargersList(),
            ],
          ),
        ),
      ],
    );
  }
}



class _StationDetailsSheet extends StatefulWidget {
  final StationModel station;

  const _StationDetailsSheet({required this.station});

  @override
  State<_StationDetailsSheet> createState() => _StationDetailsSheetState();
}

class _StationDetailsSheetState extends State<_StationDetailsSheet> {
  Map<String, dynamic>? _lastCheckIn;
  bool _isLoadingCheckIn = true;

  @override
  void initState() {
    super.initState();
    _loadLastCheckIn();
  }

  Future<void> _loadLastCheckIn() async {
    if (widget.station.id != null) {
      final checkIn = await ChargingService().getLatestStationCheckIn(widget.station.id!);
      if (mounted) {
        setState(() {
          _lastCheckIn = checkIn;
          _isLoadingCheckIn = false;
        });
      }
    } else {
      setState(() => _isLoadingCheckIn = false);
    }
  }

  String _formatLastCharged() {
    if (_lastCheckIn == null) return 'No data yet';
    try {
      final createdAt = DateTime.parse(_lastCheckIn!['created_at']);
      final now = DateTime.now();
      final diff = now.difference(createdAt);
      
      if (diff.inMinutes < 60) {
        return '${diff.inMinutes} min ago';
      } else if (diff.inHours < 24) {
        return '${diff.inHours} hrs ago';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} days ago';
      } else {
        return '${(diff.inDays / 7).floor()} weeks ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  Future<void> _launchMaps() async {
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${widget.station.location.latitude},${widget.station.location.longitude}');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final station = widget.station;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Name & Status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (station.rating != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            station.rating.toString(),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            '(${station.userRatingCount ?? 0})',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: station.status == 'working' ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  station.status.toUpperCase(),
                  style: TextStyle(
                    color: station.status == 'working' ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Address
          if (station.address != null) ...[
            Row(
              children: [
                Icon(PhosphorIcons.mapPin(PhosphorIconsStyle.duotone), size: 20, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    station.address!,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Last Charged Info
          Row(
            children: [
              Icon(PhosphorIcons.clockCounterClockwise(PhosphorIconsStyle.fill), size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Last Charged: ',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary),
              ),
              _isLoadingCheckIn
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(
                    _formatLastCharged(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 12),

          const Divider(),
          const SizedBox(height: 16),

          // Info Grid
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _InfoItem(
                icon: PhosphorIcons.plug(PhosphorIconsStyle.duotone),
                label: 'Connectors',
                value: station.connectors.join(', '),
              ),
              _InfoItem(
                icon: PhosphorIcons.currencyInr(PhosphorIconsStyle.duotone),
                label: 'Cost',
                value: station.cost ?? 'N/A',
              ),
              _InfoItem(
                icon: PhosphorIcons.car(PhosphorIconsStyle.duotone),
                label: 'Distance',
                value: '~2.5 km', // Placeholder
              ),
            ],
          ),
          
          const SizedBox(height: 24),

          // Actions
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (context) => CheckInSheet(station: station),
                    );
                  },
                  icon: Icon(PhosphorIcons.camera(PhosphorIconsStyle.duotone)),
                  label: const Text('Check-In'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _launchMaps,
                  icon: Icon(PhosphorIcons.navigationArrow(PhosphorIconsStyle.fill)),
                  label: const Text('Navigate'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.secondary)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
