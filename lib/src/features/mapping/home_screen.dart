import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../community/check_in_sheet.dart';
import 'stations_repository.dart';
import 'station_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geocoding/geocoding.dart';
import 'saved_chargers_list.dart';
import '../community/gamification_widgets.dart';
import '../authentication/user_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng? _currentCameraPosition;
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

  Future<void> _searchLocation(String query) async {
    if (query.isEmpty) return;
    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty) {
        final location = locations.first;
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
            tabs: const [
              Tab(text: 'Find Chargers'),
              Tab(text: 'Saved Chargers'),
            ],
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
                    },
                    onCameraIdle: () {
                      if (_currentCameraPosition != null) {
                        ref.read(mapCenterProvider.notifier).update(
                          ll.LatLng(_currentCameraPosition!.latitude, _currentCameraPosition!.longitude),
                        );
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
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search location...',
                          prefixIcon: const Icon(Icons.search),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: () => _searchLocation(_searchController.text),
                          ),
                        ),
                        onSubmitted: _searchLocation,
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



class _StationDetailsSheet extends StatelessWidget {
  final StationModel station;

  const _StationDetailsSheet({required this.station});

  Future<void> _launchMaps() async {
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${station.location.latitude},${station.location.longitude}');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                      builder: (context) => const CheckInSheet(),
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
