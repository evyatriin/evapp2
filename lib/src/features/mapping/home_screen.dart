import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:go_router/go_router.dart';
import '../community/check_in_sheet.dart';
import 'stations_repository.dart';
import 'station_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'saved_chargers_list.dart';
import '../community/gamification_widgets.dart';
import '../authentication/user_provider.dart';
import '../charge/charging_service.dart';
import '../charge/charge_request_sheet.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  LatLng? _currentCameraPosition;
  double _currentZoom = 12.0;
  LatLng _initialMapTarget = LatLng(
    kFallbackMapCenter.latitude,
    kFallbackMapCenter.longitude,
  );
  Position? _devicePosition;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _bootstrapMapLocation();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrapMapLocation({bool showErrors = false}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (showErrors && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Turn on location services to center the map.'),
            ),
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (showErrors && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is needed to center the map.'),
            ),
          );
        }
        return;
      }

      final position =
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          );

      if (!mounted) {
        return;
      }

      _moveMapToPosition(position, zoom: 12);
    } catch (e) {
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not determine your location: $e')),
        );
      }
    }
  }

  void _moveMapToPosition(Position position, {double zoom = 12}) {
    final target = LatLng(position.latitude, position.longitude);
    _devicePosition = position;
    _currentCameraPosition = target;
    _currentZoom = zoom;

    ref
        .read(mapCenterProvider.notifier)
        .update(ll.LatLng(position.latitude, position.longitude));
    ref.read(mapZoomProvider.notifier).update(zoom);

    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
      return;
    }

    setState(() {
      _initialMapTarget = target;
    });
  }

  void _syncMapToSearch(ll.LatLng center, double zoom) {
    final target = LatLng(center.latitude, center.longitude);
    final sameCenter =
        _currentCameraPosition != null &&
        Geolocator.distanceBetween(
              _currentCameraPosition!.latitude,
              _currentCameraPosition!.longitude,
              target.latitude,
              target.longitude,
            ) <
            25;
    final sameZoom = (_currentZoom - zoom).abs() < 0.05;

    if (sameCenter && sameZoom) {
      return;
    }

    _currentCameraPosition = target;
    _currentZoom = zoom;

    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _initialMapTarget = target;
    });
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _StationFilterSheet(),
    );
  }

  String _friendlyError(Object? error) {
    final msg = error?.toString() ?? '';
    if (msg.contains('timed out') || msg.contains('timeout')) {
      return 'Request timed out. Check your connection.';
    }
    if (msg.contains('401') || msg.contains('auth') || msg.contains('token')) {
      return 'Session expired. Please log in again.';
    }
    if (msg.contains('Network') || msg.contains('SocketException')) {
      return 'No internet connection.';
    }
    return 'Could not load chargers.';
  }

  @override
  Widget build(BuildContext context) {
    final requestedCenter = ref.watch(mapCenterProvider);
    final requestedZoom = ref.watch(mapZoomProvider);
    final stationsAsync = ref.watch(stationsProvider);
    final stations = stationsAsync.asData?.value ?? [];
    final theme = Theme.of(context);
    final activeFilterCount = totalActiveFilters(
      connectors: ref.watch(connectorFilterProvider),
      speed: ref.watch(speedFilterProvider),
      price: ref.watch(priceFilterProvider),
      availableNow: ref.watch(availableNowFilterProvider),
      access: ref.watch(accessFilterProvider),
    );
    final availableCount = stations.where((s) => s.status == 'working').length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _syncMapToSearch(requestedCenter, requestedZoom);
    });

    return Column(
      children: [
        Container(
          color: theme.colorScheme.surface,
          child: TabBar(
            controller: _tabController,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            indicatorWeight: 2,
            tabs: const [
              Tab(text: 'Nearby', height: 30),
              Tab(text: 'Saved', height: 30),
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
                    initialCameraPosition: CameraPosition(
                      target: _initialMapTarget,
                      zoom: _currentZoom,
                    ),
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                    markers:
                        stations.map((station) {
                          return Marker(
                            markerId: MarkerId(station.id),
                            position: LatLng(
                              station.location.latitude,
                              station.location.longitude,
                            ),
                            onTap: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder:
                                    (context) => DraggableScrollableSheet(
                                      initialChildSize: 0.42,
                                      minChildSize: 0.22,
                                      maxChildSize: 0.86,
                                      expand: false,
                                      builder:
                                          (context, scrollController) =>
                                              SingleChildScrollView(
                                                controller: scrollController,
                                                child: _StationDetailsSheet(
                                                  station: station,
                                                  referenceLocation:
                                                      _currentCameraPosition,
                                                ),
                                              ),
                                    ),
                              );
                            },
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                              station.isPrivate
                                  ? BitmapDescriptor
                                      .hueViolet // Private
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
                      if (_devicePosition != null) {
                        _moveMapToPosition(
                          _devicePosition!,
                          zoom: _currentZoom,
                        );
                      }
                    },
                    onCameraMove: (position) {
                      _currentCameraPosition = position.target;
                      _currentZoom = position.zoom;
                    },
                    onCameraIdle: () {
                      if (_currentCameraPosition != null) {
                        ref
                            .read(mapCenterProvider.notifier)
                            .update(
                              ll.LatLng(
                                _currentCameraPosition!.latitude,
                                _currentCameraPosition!.longitude,
                              ),
                            );
                        ref.read(mapZoomProvider.notifier).update(_currentZoom);
                      }
                    },
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                  ),

                  // Search + My Location Controls
                  Positioned(
                    bottom: 90,
                    right: 12,
                    child: Column(
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'map_search',
                          tooltip: 'Search chargers by location',
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          foregroundColor:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          elevation: 2,
                          onPressed: () => context.push('/search'),
                          child: Icon(
                            PhosphorIcons.magnifyingGlass(
                              PhosphorIconsStyle.bold,
                            ),
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(
                          heroTag: 'map_my_location',
                          tooltip: 'Center on my location',
                          backgroundColor:
                              Theme.of(context).colorScheme.surface,
                          foregroundColor:
                              Theme.of(context).colorScheme.primary,
                          elevation: 2,
                          onPressed:
                              () => _bootstrapMapLocation(showErrors: true),
                          child: const Icon(Icons.my_location, size: 20),
                        ),
                      ],
                    ),
                  ),

                  // Streak Widget Overlay
                  Positioned(
                    top: 10,
                    right: 16,
                    child: Consumer(
                      builder: (context, ref, child) {
                        final user = ref.watch(userProvider);
                        if (user == null || user.streak == 0) {
                          return const SizedBox.shrink();
                        }
                        return StreakWidget(streak: user.streak);
                      },
                    ),
                  ),

                  // Top bar: charger count pill + filter pill
                  Positioned(
                    top: 8,
                    left: 12,
                    right: 12,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _MapStatPill(
                                icon: Icons.ev_station,
                                label: '$availableCount live chargers nearby',
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Tappable filter icon button with badge
                            _FilterIconButton(
                              activeCount: activeFilterCount,
                              onTap: () => _showFilterSheet(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Loading Indicator Overlay
                  if (stationsAsync.isLoading)
                    Positioned(
                      top: 72,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
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
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.wifi_off_rounded,
                                color: theme.colorScheme.onErrorContainer,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _friendlyError(stationsAsync.error),
                                  style: TextStyle(
                                    color: theme.colorScheme.onErrorContainer,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed:
                                    () => ref.invalidate(stationsProvider),
                                style: TextButton.styleFrom(
                                  foregroundColor:
                                      theme.colorScheme.onErrorContainer,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text(
                                  'Retry',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
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
  final LatLng? referenceLocation;

  const _StationDetailsSheet({required this.station, this.referenceLocation});

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
    final checkIn = await ChargingService().getLatestStationCheckIn(
      widget.station.id,
    );
    if (mounted) {
      setState(() {
        _lastCheckIn = checkIn;
        _isLoadingCheckIn = false;
      });
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

  String? _formatDistance() {
    final reference = widget.referenceLocation;
    if (reference == null) return null;

    final meters = Geolocator.distanceBetween(
      reference.latitude,
      reference.longitude,
      widget.station.location.latitude,
      widget.station.location.longitude,
    );
    if (meters < 1000) {
      return '${meters.round()} m';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Future<void> _launchMaps() async {
    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${widget.station.location.latitude},${widget.station.location.longitude}',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  Future<void> _openChargeRequestSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ChargeRequestSheet(station: widget.station),
    );

    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Charge request sent. You can track it in Community Charging.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final station = widget.station;
    final distance = _formatDistance();
    final statusTone =
        station.status == 'working'
            ? theme.colorScheme.primary
            : theme.colorScheme.error;
    final infoItems = <Widget>[
      _InfoItem(
        icon: PhosphorIcons.plug(PhosphorIconsStyle.duotone),
        label: 'Connectors',
        value:
            station.connectors.isNotEmpty
                ? station.connectors.join(', ')
                : 'Not specified',
      ),
      _InfoItem(
        icon: PhosphorIcons.clockCounterClockwise(PhosphorIconsStyle.duotone),
        label: 'Updated',
        value: _isLoadingCheckIn ? '--' : _formatLastCharged(),
      ),
    ];

    if (distance != null) {
      infoItems.insert(
        1,
        _InfoItem(
          icon: PhosphorIcons.mapPin(PhosphorIconsStyle.duotone),
          label: 'Distance',
          value: distance,
        ),
      );
    }
    if (station.provider != null && station.provider!.trim().isNotEmpty) {
      infoItems.add(
        _InfoItem(
          icon: PhosphorIcons.buildings(PhosphorIconsStyle.duotone),
          label: 'Network',
          value: station.provider!,
        ),
      );
    }
    if (station.cost != null && station.cost!.trim().isNotEmpty) {
      infoItems.add(
        _InfoItem(
          icon: PhosphorIcons.currencyInr(PhosphorIconsStyle.duotone),
          label: 'Cost',
          value: station.cost!,
        ),
      );
    }
    if (station.availabilityStatus != null &&
        station.availabilityStatus!.trim().isNotEmpty) {
      infoItems.add(
        _InfoItem(
          icon: PhosphorIcons.pulse(PhosphorIconsStyle.duotone),
          label: 'Availability',
          value: station.availabilityStatus!,
        ),
      );
    }
    if (station.isPrivate) {
      infoItems.add(
        _InfoItem(
          icon: PhosphorIcons.houseLine(PhosphorIconsStyle.duotone),
          label: 'Host',
          value: station.hostName ?? 'Community host',
        ),
      );
      if (station.pricePerKwh != null || station.pricePerSession != null) {
        infoItems.add(
          _InfoItem(
            icon: PhosphorIcons.currencyInr(PhosphorIconsStyle.duotone),
            label: 'Host rate',
            value: [
              if (station.pricePerKwh != null)
                'Rs ${station.pricePerKwh!.toStringAsFixed(0)}/kWh',
              if (station.pricePerSession != null)
                'Rs ${station.pricePerSession!.toStringAsFixed(0)}/session',
            ].join(' • '),
          ),
        );
      }
    }
    return Container(
      padding: const EdgeInsets.all(18),
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
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (station.rating != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            station.rating.toString(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.star,
                            size: 16,
                            color: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '(${station.userRatingCount ?? 0})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.secondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusTone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  station.status.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusTone,
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
                Icon(
                  PhosphorIcons.mapPin(PhosphorIconsStyle.duotone),
                  size: 20,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    station.address!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
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
              Icon(
                PhosphorIcons.clockCounterClockwise(PhosphorIconsStyle.fill),
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Last Charged: ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
              _isLoadingCheckIn
                  ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
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
          Wrap(spacing: 10, runSpacing: 10, children: infoItems),

          const SizedBox(height: 24),

          // Actions
          if ((station.parkingNotes ?? '').isNotEmpty) ...[
            Text(
              'Parking notes',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(station.parkingNotes!),
            const SizedBox(height: 12),
          ],
          if ((station.houseRules ?? '').isNotEmpty) ...[
            Text(
              'House rules',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(station.houseRules!),
            const SizedBox(height: 12),
          ],
          if (station.isPrivate &&
              station.isAcceptingRequests &&
              (station.stationRecordId ?? '').isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openChargeRequestSheet,
                icon: Icon(PhosphorIcons.handshake(PhosphorIconsStyle.fill)),
                label: const Text('Request Charging'),
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                  label: const Text('Share Update'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _launchMaps,
                  icon: Icon(
                    PhosphorIcons.navigationArrow(PhosphorIconsStyle.fill),
                  ),
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

class _FilterIconButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onTap;

  const _FilterIconButton({required this.activeCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = activeCount > 0;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surface.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.tune,
              size: 20,
              color:
                  isActive
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
            ),
          ),
          if (isActive)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  '$activeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapStatPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MapStatPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.colorScheme.surface.withValues(alpha: 0.94);
    final fg = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Station Filter Sheet
// ---------------------------------------------------------------------------

class _StationFilterSheet extends ConsumerWidget {
  const _StationFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final connectors = ref.watch(connectorFilterProvider);
    final speed = ref.watch(speedFilterProvider);
    final price = ref.watch(priceFilterProvider);
    final availableNow = ref.watch(availableNowFilterProvider);
    final access = ref.watch(accessFilterProvider);

    final totalActive = totalActiveFilters(
      connectors: connectors,
      speed: speed,
      price: price,
      availableNow: availableNow,
      access: access,
    );

    void resetAll() {
      ref.read(connectorFilterProvider.notifier).clear();
      ref.read(speedFilterProvider.notifier).clear();
      ref.read(priceFilterProvider.notifier).clear();
      ref.read(availableNowFilterProvider.notifier).clear();
      ref.read(accessFilterProvider.notifier).clear();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.tune, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Filter Chargers',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (totalActive > 0)
                  TextButton(
                    onPressed: resetAll,
                    child: const Text('Reset all'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 16),

            // ── Connector Type ──────────────────────────────────────────────
            _FilterSection(
              label: 'Connector Type',
              chips: const ['CCS2', 'Type 2', 'CHAdeMO', 'GB/T'],
              selected: connectors,
              onToggle:
                  (v) => ref.read(connectorFilterProvider.notifier).toggle(v),
            ),
            const SizedBox(height: 16),

            // ── Charging Speed ──────────────────────────────────────────────
            _FilterSection(
              label: 'Charging Speed',
              chips: const ['DC Fast (50+ kW)', 'AC (up to 22 kW)'],
              selected: speed,
              onToggle: (v) {
                // Normalise to short keys used in repository
                final key = v.startsWith('DC') ? 'DC Fast' : 'AC';
                ref.read(speedFilterProvider.notifier).toggle(key);
              },
              chipLabel: (chip) => chip, // already descriptive
              isSelected:
                  (chip) =>
                      chip.startsWith('DC')
                          ? speed.contains('DC Fast')
                          : speed.contains('AC'),
            ),
            const SizedBox(height: 16),

            // ── Price ───────────────────────────────────────────────────────
            _FilterSection(
              label: 'Price',
              chips: const ['Free', 'Paid', 'Community'],
              selected: price,
              onToggle: (v) => ref.read(priceFilterProvider.notifier).toggle(v),
            ),
            const SizedBox(height: 16),

            // ── Access Type ─────────────────────────────────────────────────
            _FilterSection(
              label: 'Access',
              chips: const ['Public', 'Community Hosted'],
              selected: access,
              onToggle:
                  (v) => ref.read(accessFilterProvider.notifier).toggle(v),
            ),
            const SizedBox(height: 16),

            // ── Availability toggle ─────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color:
                    availableNow
                        ? theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.4,
                        )
                        : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                value: availableNow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 2,
                ),
                title: const Text(
                  'Available now only',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text('Hide busy and offline stations'),
                secondary: Icon(
                  Icons.bolt,
                  color:
                      availableNow
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                ),
                onChanged:
                    (_) =>
                        ref.read(availableNowFilterProvider.notifier).toggle(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String label;
  final List<String> chips;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String Function(String)? chipLabel;
  final bool Function(String)? isSelected;

  const _FilterSection({
    required this.label,
    required this.chips,
    required this.selected,
    required this.onToggle,
    this.chipLabel,
    this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children:
              chips.map((chip) {
                final sel =
                    isSelected != null
                        ? isSelected!(chip)
                        : selected.contains(chip);
                final display = chipLabel != null ? chipLabel!(chip) : chip;
                return FilterChip(
                  label: Text(display),
                  selected: sel,
                  onSelected: (_) => onToggle(chip),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: -1,
                    vertical: -1,
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 110, maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary, size: 18),
            const SizedBox(height: 6),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
