import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gap/gap.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../authentication/auth_service.dart';
import 'route_model.dart';
import 'route_planner_screen.dart'; // For TripSummarySheet
import 'route_service.dart';
import 'saved_route_model.dart';

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
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _routes = widget.extra['routes'] as List<RouteModel>;
    _vehicleId = widget.extra['vehicleId'] as String?;
    _startAddress = widget.extra['startAddress'] as String?;
    _endAddress = widget.extra['endAddress'] as String?;

    _selectedRoute = _routes.isNotEmpty ? _routes.first : null;
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
                    child: Icon(icon, color: color, size: 34),
                  );
                }).toList(),
              ),
            ],
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
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color:
                                              isSelected
                                                  ? theme.colorScheme.primary
                                                  : theme
                                                      .colorScheme
                                                      .surfaceContainerHighest,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  isSelected
                                                      ? theme
                                                          .colorScheme
                                                          .onPrimary
                                                      : theme
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const Gap(8),
                                      Expanded(
                                        child: Text(
                                          route.name,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                          onChanged: (RouteModel? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedRoute = newValue;
                              });
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
}
