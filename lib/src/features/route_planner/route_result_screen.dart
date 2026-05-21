import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gap/gap.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:map_launcher/map_launcher.dart';

import '../authentication/auth_service.dart';
import 'charger_along_route_model.dart';
import 'charger_route_service.dart';
import 'route_model.dart';
import 'route_planner_screen.dart'; // For TripSummarySheet
import 'route_service.dart';
import 'saved_route_model.dart';
import 'widgets/charger_details_sheet.dart';
import 'widgets/charger_map_marker.dart';

class RouteResultScreen extends StatefulWidget {
  final Map<String, dynamic> extra;

  const RouteResultScreen({super.key, required this.extra});

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen> {
  late List<RouteModel> _routes;
  RouteModel? _selectedRoute;
  String? _vehicleId;
  String? _startAddress;
  String? _endAddress;
  final MapController _mapController = MapController();

  static final ll.LatLng _initialCenter = ll.LatLng(20.5937, 78.9629);
  final _routeService = RouteService();
  final _authService = AuthService();
  final _chargerRouteService = ChargerRouteService();
  bool _isSaving = false;

  // Chargers state
  List<ChargerAlongRoute> _chargersAlongRoute = [];
  bool _loadingChargers = false;
  bool _showChargersOnMap = true;

  @override
  void initState() {
    super.initState();
    _routes = widget.extra['routes'] as List<RouteModel>;
    _vehicleId = widget.extra['vehicleId'] as String?;
    _startAddress = widget.extra['startAddress'] as String?;
    _endAddress = widget.extra['endAddress'] as String?;

    _selectedRoute = _routes.isNotEmpty ? _routes.first : null;

    // Fetch chargers along the selected route
    if (_selectedRoute != null) {
      _fetchChargersAlongRoute(_selectedRoute!);
    }
  }

  Future<void> _fetchChargersAlongRoute(RouteModel route) async {
    if (!mounted) return;

    setState(() => _loadingChargers = true);

    try {
      // Get origin and destination from the first and last stop
      final origin = route.stops.isNotEmpty ? route.stops.first.location : null;
      final destination = route.stops.isNotEmpty ? route.stops.last.location : null;

      if (origin == null || destination == null) {
        setState(() => _loadingChargers = false);
        return;
      }

      // Convert polyline to LatLng list
      final polyline = route.polyline
          .map((p) => ll.LatLng(p.latitude, p.longitude))
          .toList();

      final chargers = await _chargerRouteService.getChargersAlongRoute(
        origin: origin,
        destination: destination,
        polyline: polyline,
        radiusKm: 25.0, // Search within 25km of route
      );

      if (mounted) {
        setState(() {
          _chargersAlongRoute = chargers;
          _loadingChargers = false;
        });

        debugPrint('Loaded ${chargers.length} chargers along route');
      }
    } catch (e) {
      debugPrint('Error fetching chargers: $e');
      if (mounted) {
        setState(() => _loadingChargers = false);
      }
    }
  }

  Future<void> _saveRoute() async {
    final selectedRoute = _selectedRoute;
    if (selectedRoute == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No route is available to save.')),
      );
      return;
    }

    final userId = _authService.currentUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to save routes')),
      );
      return;
    }

    // Safety check: Ensure route has stops
    if (selectedRoute.stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Error: Route has no stops. Please try planning the route again.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final savedRoute = SavedRoute(
        id:
            DateTime.now().millisecondsSinceEpoch
                .toString(), // Temp ID, backend should generate
        userId: userId,
        name: '${_startAddress ?? "Start"} to ${_endAddress ?? "End"}',
        startLocation: selectedRoute.stops.first.location,
        startAddress: _startAddress ?? 'Unknown Start',
        endLocation: selectedRoute.stops.last.location,
        endAddress: _endAddress ?? 'Unknown Destination',
        vehicleId: _vehicleId,
        routeData: selectedRoute,
        distanceKm: selectedRoute.totalDistanceKm,
        durationMin: selectedRoute.totalDurationMin.round(),
        chargingStops:
            selectedRoute.stops
                .where((s) => s.type == StopType.charging)
                .length,
        createdAt: DateTime.now(),
      );

      await _routeService.saveRoute(savedRoute);

      if (mounted) {
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Route Saved!'),
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map, size: 48),
                    Gap(16),
                    Text('You earned +5 Points!'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving route: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedRoute = _selectedRoute;

    if (selectedRoute == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Route Results')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.route_outlined, size: 56),
                const Gap(16),
                Text(
                  'No route could be planned for these settings.',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const Gap(8),
                Text(
                  'Try another destination or adjust the charge targets and battery health.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const Gap(20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to Planner'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: 7.5,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onMapReady: () {
                final bounds = _buildBounds(selectedRoute);
                if (bounds != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    _mapController.fitCamera(
                      CameraFit.bounds(
                        bounds: bounds,
                        padding: const EdgeInsets.fromLTRB(18, 64, 18, 104),
                      ),
                    );
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.evranger.ev_router_app2',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: selectedRoute.polyline
                        .map((p) => ll.LatLng(p.latitude, p.longitude))
                        .toList(),
                    color: theme.colorScheme.primary,
                    strokeWidth: 5,
                  ),
                ],
              ),
              MarkerLayer(
                markers: selectedRoute.stops.map((stop) {
                  final colorScheme = theme.colorScheme;
                  final color =
                      stop.type == StopType.charging
                          ? colorScheme.primary
                          : (stop.type == StopType.origin ||
                                  stop.type == StopType.destination)
                              ? colorScheme.error
                              : colorScheme.tertiary;
                  final icon =
                      stop.type == StopType.charging
                          ? Icons.ev_station
                          : stop.type == StopType.origin
                              ? Icons.trip_origin
                              : stop.type == StopType.destination
                                  ? Icons.location_pin
                                  : Icons.place;

                  return Marker(
                    point: ll.LatLng(
                      stop.location.latitude,
                      stop.location.longitude,
                    ),
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap:
                          stop.type == StopType.charging
                              ? () => _showChargingStopDetails(stop)
                              : null,
                      child: Icon(icon, color: color, size: 34),
                    ),
                  );
                }).toList(),
              ),
              // Dashed connector lines: off-route charger → nearest route point
              if (_showChargersOnMap && _chargersAlongRoute.isNotEmpty)
                ChargersConnectorLayer(chargers: _chargersAlongRoute),
              // Charger markers on top of connector lines
              if (_showChargersOnMap && _chargersAlongRoute.isNotEmpty)
                ChargersMarkerLayer(
                  chargers: _chargersAlongRoute,
                  onChargerTap: (charger) => _showChargerDetails(charger),
                  showOptimalOnly: false,
                ),
            ],
          ),

          // Chargers Loading Indicator
          if (_loadingChargers)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                          theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const Gap(8),
                    Text(
                      'Loading chargers...',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),

          // Chargers Loaded Badge
          if (!_loadingChargers && _chargersAlongRoute.isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 60,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  border: Border.all(color: Colors.green, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.ev_station,
                      size: 14,
                      color: Colors.green,
                    ),
                    const Gap(6),
                    Text(
                      '${_chargersAlongRoute.length} chargers found',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Floating Header with Back Button + Route Selector
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 8,
            right: 8,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Back Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: theme.colorScheme.onSurface,
                          size: 18,
                        ),
                      ),
                    ),
                  ),

                  // Charger Toggle Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _showChargersOnMap = !_showChargersOnMap;
                        });
                      },
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          _showChargersOnMap ? Icons.ev_station : Icons.power_off_outlined,
                          color: _showChargersOnMap
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          size: 18,
                        ),
                      ),
                    ),
                  ),

                  // Divider
                  Container(
                    width: 1,
                    height: 32,
                    color: theme.colorScheme.outlineVariant,
                  ),

                  // Route Selector
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<RouteModel>(
                          value: selectedRoute,
                          isExpanded: true,
                          isDense: true,
                          icon: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: theme.colorScheme.primary,
                              size: 16,
                            ),
                          ),
                          items:
                              _routes.asMap().entries.map((entry) {
                                final index = entry.key;
                                final route = entry.value;
                                final isSelected =
                                    route.id == selectedRoute.id;
                                return DropdownMenuItem(
                                  value: route,
                                  child: _RouteDropdownLabel(
                                    route: route,
                                    index: index + 1,
                                    isSelected: isSelected,
                                    compact: false,
                                  ),
                                );
                              }).toList(),
                          selectedItemBuilder:
                              (context) => _routes.asMap().entries.map((entry) {
                                final route = entry.value;
                                return _RouteDropdownLabel(
                                  route: route,
                                  index: entry.key + 1,
                                  isSelected: route.id == selectedRoute.id,
                                  compact: true,
                                );
                              }).toList(),
                          onChanged: (RouteModel? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedRoute = newValue;
                              });
                              // Fetch chargers for the new route
                              _fetchChargersAlongRoute(newValue);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Trip Summary Sheet (Persistent Bottom)
          Align(
            alignment: Alignment.bottomCenter,
            child: TripSummarySheet(
              route: selectedRoute,
              onSave: _saveRoute,
              isSaving: _isSaving,
            ),
          ),
        ],
      ),
    );
  }

  LatLngBounds? _buildBounds(RouteModel route) {
    if (route.polyline.isEmpty) return null;

    double minLat = route.polyline.first.latitude;
    double maxLat = route.polyline.first.latitude;
    double minLng = route.polyline.first.longitude;
    double maxLng = route.polyline.first.longitude;

    for (final point in route.polyline) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      ll.LatLng(minLat, minLng),
      ll.LatLng(maxLat, maxLng),
    );
  }

  Future<void> _showChargingStopDetails(RouteStop stop) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (sheetContext) => ChargingStopDetailsSheet(
            stop: stop,
            onOpenInMaps: () async {
              Navigator.of(sheetContext).pop();
              await _openChargingStopInMaps(stop);
            },
          ),
    );
  }

  Future<void> _openChargingStopInMaps(RouteStop stop) async {
    try {
      final availableMaps = await MapLauncher.installedMaps;
      if (availableMaps.isEmpty) {
        if (mounted) {
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open charging stop: $e')),
        );
      }
    }
  }

  Future<void> _showChargerDetails(ChargerAlongRoute charger) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => ChargerDetailsSheet(
        charger: charger,
        onOpenInMaps: () async {
          Navigator.of(sheetContext).pop();
          await _openChargerInMaps(charger);
        },
      ),
    );
  }

  Future<void> _openChargerInMaps(ChargerAlongRoute charger) async {
    try {
      final availableMaps = await MapLauncher.installedMaps;
      if (availableMaps.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No map apps installed')),
          );
        }
        return;
      }

      await availableMaps.first.showMarker(
        coords: Coords(charger.latitude, charger.longitude),
        title: charger.name,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open charger: $e')),
        );
      }
    }
  }
}

class _RouteDropdownLabel extends StatelessWidget {
  final RouteModel route;
  final int index;
  final bool isSelected;
  final bool compact;

  const _RouteDropdownLabel({
    required this.route,
    required this.index,
    required this.isSelected,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta =
        '${route.totalDistanceKm.toStringAsFixed(1)} km • ${route.totalChargeDurationMin} min charge • ₹${route.estimatedCost.toStringAsFixed(0)}';
    final badge = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color:
            isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          '$index',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color:
                isSelected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    if (compact) {
      return Row(
        children: [
          badge,
          const Gap(8),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: route.name,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  TextSpan(
                    text: '  $meta',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        badge,
        const Gap(8),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                meta,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
